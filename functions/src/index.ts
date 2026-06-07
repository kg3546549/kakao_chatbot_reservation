import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

initializeApp();

const db = getFirestore();
const region = "asia-northeast3";

type Role = "owner" | "manager" | "viewer" | "botDevice";

async function requireMembership(uid: string, tenantId: string, roles?: Role[]) {
  const member = await db.doc(`tenants/${tenantId}/members/${uid}`).get();
  if (!member.exists || member.get("status") !== "active") {
    throw new HttpsError("permission-denied", "활성화된 가게 멤버가 아닙니다.");
  }
  if (roles && !roles.includes(member.get("role") as Role)) {
    throw new HttpsError("permission-denied", "요청을 수행할 권한이 없습니다.");
  }
  return member;
}

export const createTenant = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  const name = String(request.data?.name ?? "").trim();
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!name) throw new HttpsError("invalid-argument", "가게 이름이 필요합니다.");

  const tenantId = randomUUID();
  const tenantRef = db.doc(`tenants/${tenantId}`);
  const memberRef = tenantRef.collection("members").doc(uid);
  const userMembershipRef = db.doc(`users/${uid}/tenantMemberships/${tenantId}`);
  const batch = db.batch();

  batch.create(tenantRef, {
    name,
    status: "active",
    timezone: "Asia/Seoul",
    createdAt: FieldValue.serverTimestamp(),
    createdBy: uid,
  });
  batch.create(memberRef, {
    role: "owner",
    status: "active",
    joinedAt: FieldValue.serverTimestamp(),
  });
  batch.create(userMembershipRef, {
    tenantId,
    tenantName: name,
    role: "owner",
    status: "active",
    joinedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return { tenantId };
});

export const registerDevice = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  const mode = request.data?.mode === "bot" ? "bot" : "admin";
  const fcmToken = String(request.data?.fcmToken ?? "");

  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !deviceId) {
    throw new HttpsError("invalid-argument", "tenantId와 deviceId가 필요합니다.");
  }
  await requireMembership(
    uid,
    tenantId,
    mode === "bot" ? ["owner", "manager", "botDevice"] : undefined,
  );

  await db.doc(`tenants/${tenantId}/devices/${deviceId}`).set({
    uid,
    mode,
    fcmToken,
    status: "active",
    lastSeenAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true };
});

export const unregisterDevice = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !deviceId) {
    throw new HttpsError("invalid-argument", "tenantId와 deviceId가 필요합니다.");
  }
  await requireMembership(uid, tenantId);

  const deviceRef = db.doc(`tenants/${tenantId}/devices/${deviceId}`);
  const device = await deviceRef.get();
  if (device.exists && device.get("uid") !== uid) {
    throw new HttpsError("permission-denied", "다른 사용자의 기기입니다.");
  }
  await deviceRef.set({
    status: "inactive",
    fcmToken: "",
    lastSeenAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true };
});

export const createReservationEvent = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const eventId = String(request.data?.eventId ?? "");
  const reservationId = String(request.data?.reservationId ?? "");
  const type = String(request.data?.type ?? "created");
  const itemId = String(request.data?.itemId ?? "");
  const businessDate = String(request.data?.businessDate ?? "");

  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !eventId || !reservationId) {
    throw new HttpsError("invalid-argument", "필수 예약 식별자가 없습니다.");
  }
  await requireMembership(uid, tenantId, ["owner", "manager", "botDevice"]);

  const eventRef = db.doc(`tenants/${tenantId}/reservationEvents/${eventId}`);
  const reservationRef = db.doc(
    `tenants/${tenantId}/currentReservations/${reservationId}`,
  );
  await db.runTransaction(async (transaction) => {
    if ((await transaction.get(eventRef)).exists) return;
    transaction.create(eventRef, {
      eventId,
      reservationId,
      type,
      itemId,
      itemName: String(request.data?.itemName ?? ""),
      nickname: String(request.data?.nickname ?? ""),
      roomName: String(request.data?.roomName ?? ""),
      businessDate,
      sourceDeviceId: String(request.data?.sourceDeviceId ?? ""),
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
    });

    if (type === "created") {
      transaction.set(reservationRef, {
        reservationId,
        itemId,
        itemName: String(request.data?.itemName ?? ""),
        nickname: String(request.data?.nickname ?? ""),
        roomName: String(request.data?.roomName ?? ""),
        businessDate,
        sourceDeviceId: String(request.data?.sourceDeviceId ?? ""),
        createdBy: uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (type === "cancelled") {
      transaction.delete(reservationRef);
    }
  });

  if (type === "reset") {
    const reservations = await db.collection(`tenants/${tenantId}/currentReservations`)
      .where("itemId", "==", itemId)
      .where("businessDate", "==", businessDate)
      .get();
    const batch = db.batch();
    reservations.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  return { success: true };
});

export const notifyReservationCreated = onDocumentCreated(
  { region, document: "tenants/{tenantId}/reservationEvents/{eventId}" },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.type !== "created") return;

    const devices = await db.collection(`tenants/${event.params.tenantId}/devices`)
      .where("mode", "==", "admin")
      .where("status", "==", "active")
      .get();
    const tokens = devices.docs.map((doc) => String(doc.get("fcmToken") ?? ""))
      .filter(Boolean);
    if (tokens.length === 0) return;

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "새 예약이 들어왔습니다",
        body: `${data.nickname || "고객"}님의 예약이 등록되었습니다.`,
      },
      data: {
        type: "reservation_created",
        tenantId: event.params.tenantId,
        reservationId: String(data.reservationId),
        itemId: String(data.itemId ?? ""),
      },
      android: {
        priority: "high",
        notification: { channelId: "reservation_updates" },
      },
    });
  },
);
