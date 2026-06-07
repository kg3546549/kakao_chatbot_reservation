import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

initializeApp();

const db = getFirestore();
const region = "asia-northeast3";
const bootstrapAdminEmail = "kg354654932@gmail.com";

type Role = "owner" | "manager" | "viewer" | "botDevice";

function requirePlatformAdmin(request: { auth?: { token?: Record<string, unknown> } }) {
  if (request.auth?.token?.platformAdmin !== true) {
    throw new HttpsError("permission-denied", "플랫폼 관리자 권한이 필요합니다.");
  }
}

async function requireMembership(uid: string, tenantId: string, roles?: Role[]) {
  const tenant = await db.doc(`tenants/${tenantId}`).get();
  if (!tenant.exists || tenant.get("status") !== "active") {
    throw new HttpsError("failed-precondition", "현재 이용할 수 없는 가게입니다.");
  }
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

export const updateTenantStatus = onCall({ region }, async (request) => {
  requirePlatformAdmin(request);
  const tenantId = String(request.data?.tenantId ?? "");
  const status = String(request.data?.status ?? "");
  if (!tenantId || !["active", "suspended"].includes(status)) {
    throw new HttpsError("invalid-argument", "유효한 tenantId와 status가 필요합니다.");
  }
  const tenantRef = db.doc(`tenants/${tenantId}`);
  await tenantRef.set({
    status,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: request.auth?.uid,
  }, { merge: true });
  await tenantRef.collection("auditLogs").add({
    action: "tenant_status_changed",
    status,
    actorUid: request.auth?.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { success: true };
});

export const bootstrapPlatformAdmin = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (request.auth?.token.email !== bootstrapAdminEmail) {
    throw new HttpsError(
      "permission-denied",
      "지정된 최초 플랫폼 관리자 계정만 설정할 수 있습니다.",
    );
  }
  const bootstrapRef = db.doc("system/platformAdminBootstrap");

  await db.runTransaction(async (transaction) => {
    if ((await transaction.get(bootstrapRef)).exists) {
      throw new HttpsError(
        "failed-precondition",
        "플랫폼 관리자가 이미 설정되어 있습니다.",
      );
    }
    transaction.create(bootstrapRef, {
      uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  try {
    const user = await getAuth().getUser(uid);
    await getAuth().setCustomUserClaims(uid, {
      ...user.customClaims,
      platformAdmin: true,
    });
  } catch (error) {
    await bootstrapRef.delete();
    throw error;
  }
  return { success: true };
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

export const addTenantMember = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const email = String(request.data?.email ?? "").trim().toLowerCase();
  const role = String(request.data?.role ?? "viewer") as Role;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !email) {
    throw new HttpsError("invalid-argument", "tenantId와 이메일이 필요합니다.");
  }
  if (!["owner", "manager", "viewer", "botDevice"].includes(role)) {
    throw new HttpsError("invalid-argument", "유효하지 않은 역할입니다.");
  }
  await requireMembership(uid, tenantId, ["owner"]);

  let targetUser;
  try {
    targetUser = await getAuth().getUserByEmail(email);
  } catch {
    throw new HttpsError(
      "not-found",
      "해당 이메일 계정이 없습니다. 사용자가 먼저 앱에서 계정을 생성해야 합니다.",
    );
  }

  const tenant = await db.doc(`tenants/${tenantId}`).get();
  const tenantName = String(tenant.get("name") ?? "");
  const memberRef = db.doc(`tenants/${tenantId}/members/${targetUser.uid}`);
  const userMembershipRef =
    db.doc(`users/${targetUser.uid}/tenantMemberships/${tenantId}`);
  const batch = db.batch();
  batch.set(memberRef, {
    email,
    role,
    status: "active",
    joinedAt: FieldValue.serverTimestamp(),
    addedBy: uid,
  }, { merge: true });
  batch.set(userMembershipRef, {
    tenantId,
    tenantName,
    role,
    status: "active",
    joinedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
  return { success: true, uid: targetUser.uid };
});

export const removeTenantMember = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const memberUid = String(request.data?.memberUid ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !memberUid) {
    throw new HttpsError("invalid-argument", "tenantId와 memberUid가 필요합니다.");
  }
  await requireMembership(uid, tenantId, ["owner"]);
  if (memberUid === uid) {
    throw new HttpsError("failed-precondition", "본인 owner 권한은 제거할 수 없습니다.");
  }

  const batch = db.batch();
  batch.set(db.doc(`tenants/${tenantId}/members/${memberUid}`), {
    status: "inactive",
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(db.doc(`users/${memberUid}/tenantMemberships/${tenantId}`), {
    status: "inactive",
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
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
    const writer = db.bulkWriter();
    reservations.docs.forEach((doc) => writer.delete(doc.ref));
    await writer.close();
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
    const recipients = devices.docs
      .map((doc) => ({ doc, token: String(doc.get("fcmToken") ?? "") }))
      .filter((recipient) => recipient.token.length > 0);

    for (let offset = 0; offset < recipients.length; offset += 500) {
      const chunk = recipients.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: chunk.map((recipient) => recipient.token),
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

      const writer = db.bulkWriter();
      response.responses.forEach((result, index) => {
        if (!result.success && isInvalidFcmToken(result.error?.code)) {
          writer.set(chunk[index].doc.ref, {
            fcmToken: "",
            status: "inactive",
            updatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      });
      await writer.close();
    }
  },
);

function isInvalidFcmToken(code?: string) {
  return code === "messaging/invalid-registration-token"
    || code === "messaging/registration-token-not-registered";
}

export const aggregateDailyReservationStats = onDocumentCreated(
  { region, document: "tenants/{tenantId}/reservationEvents/{eventId}" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const businessDate = String(data.businessDate ?? "");
    if (!businessDate) return;

    const statsRef =
      db.doc(`tenants/${event.params.tenantId}/dailyStats/${businessDate}`);
    const updates: Record<string, unknown> = {
      businessDate,
      updatedAt: FieldValue.serverTimestamp(),
      totalEvents: FieldValue.increment(1),
    };
    if (data.type === "created") {
      updates.createdCount = FieldValue.increment(1);
      updates.activeDelta = FieldValue.increment(1);
    } else if (data.type === "cancelled") {
      updates.cancelledCount = FieldValue.increment(1);
      updates.activeDelta = FieldValue.increment(-1);
    } else if (data.type === "reset") {
      updates.resetCount = FieldValue.increment(1);
    }
    await statsRef.set(updates, { merge: true });
  },
);
