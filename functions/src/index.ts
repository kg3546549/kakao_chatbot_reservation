import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

initializeApp();

const db = getFirestore();
const region = "asia-northeast3";
const bootstrapAdminEmail = defineString("BOOTSTRAP_ADMIN_EMAIL");
const callableOptions = { region, enforceAppCheck: false };

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

async function requireItemManagementAccess(
  uid: string,
  tenantId: string,
  sourceDeviceId: string,
) {
  const member = await requireMembership(
    uid,
    tenantId,
    ["owner", "manager", "botDevice"],
  );
  if (member.get("role") !== "botDevice") return;

  const [tenant, device] = await Promise.all([
    db.doc(`tenants/${tenantId}`).get(),
    db.doc(`tenants/${tenantId}/devices/${sourceDeviceId}`).get(),
  ]);
  if (
    !sourceDeviceId
    || tenant.get("activeBotDeviceId") !== sourceDeviceId
    || !device.exists
    || device.get("uid") !== uid
    || device.get("mode") !== "bot"
    || device.get("status") !== "active"
  ) {
    throw new HttpsError("permission-denied", "활성 예약봇 기기가 아닙니다.");
  }
}

async function requireActiveBotDevice(
  uid: string,
  tenantId: string,
  deviceId: string,
) {
  await requireMembership(uid, tenantId, ["owner", "manager", "botDevice"]);
  const [tenant, device] = await Promise.all([
    db.doc(`tenants/${tenantId}`).get(),
    db.doc(`tenants/${tenantId}/devices/${deviceId}`).get(),
  ]);
  if (
    !deviceId
    || tenant.get("activeBotDeviceId") !== deviceId
    || !device.exists
    || device.get("uid") !== uid
    || device.get("mode") !== "bot"
    || device.get("status") !== "active"
  ) {
    throw new HttpsError("permission-denied", "활성 예약봇 기기가 아닙니다.");
  }
}

export const createTenant = onCall(callableOptions, async (request) => {
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

export const updateTenantStatus = onCall(callableOptions, async (request) => {
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

export const bootstrapPlatformAdmin = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (request.auth?.token.email !== bootstrapAdminEmail.value()) {
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

export const registerDevice = onCall(callableOptions, async (request) => {
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

  const tenantRef = db.doc(`tenants/${tenantId}`);
  const deviceRef = tenantRef.collection("devices").doc(deviceId);
  await db.runTransaction(async (transaction) => {
    if (mode === "bot") {
      const tenant = await transaction.get(tenantRef);
      const activeBotDeviceId = String(tenant.get("activeBotDeviceId") ?? "");
      if (activeBotDeviceId && activeBotDeviceId !== deviceId) {
        throw new HttpsError(
          "failed-precondition",
          "다른 기기가 이미 예약봇으로 실행 중입니다.",
        );
      }
      transaction.set(tenantRef, {
        activeBotDeviceId: deviceId,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    transaction.set(deviceRef, {
      uid,
      mode,
      fcmToken,
      status: "active",
      lastSeenAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { success: true };
});

export const unregisterDevice = onCall(callableOptions, async (request) => {
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
  const tenantRef = db.doc(`tenants/${tenantId}`);
  await db.runTransaction(async (transaction) => {
    const tenant = await transaction.get(tenantRef);
    if (tenant.get("activeBotDeviceId") === deviceId) {
      transaction.set(tenantRef, {
        activeBotDeviceId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    transaction.set(deviceRef, {
      status: "inactive",
      fcmToken: "",
      lastSeenAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { success: true };
});

export const releaseBotDevice = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !deviceId) {
    throw new HttpsError("invalid-argument", "tenantId와 deviceId가 필요합니다.");
  }
  await requireMembership(uid, tenantId, ["owner", "manager"]);

  const tenantRef = db.doc(`tenants/${tenantId}`);
  const deviceRef = tenantRef.collection("devices").doc(deviceId);
  await db.runTransaction(async (transaction) => {
    const tenant = await transaction.get(tenantRef);
    if (tenant.get("activeBotDeviceId") === deviceId) {
      transaction.set(tenantRef, {
        activeBotDeviceId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    transaction.set(deviceRef, {
      status: "inactive",
      fcmToken: "",
      releasedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { success: true };
});

export const addTenantMember = onCall(callableOptions, async (request) => {
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

export const removeTenantMember = onCall(callableOptions, async (request) => {
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

export const upsertItem = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const itemId = String(request.data?.itemId ?? "");
  const name = String(request.data?.name ?? "").trim();
  const maxCapacity = Number(request.data?.maxCapacity ?? 0);
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !itemId || !name || !Number.isInteger(maxCapacity) || maxCapacity <= 0) {
    throw new HttpsError("invalid-argument", "유효한 예약 항목 정보가 필요합니다.");
  }
  await requireItemManagementAccess(
    uid,
    tenantId,
    String(request.data?.sourceDeviceId ?? ""),
  );

  await db.doc(`tenants/${tenantId}/items/${itemId}`).set({
    itemId,
    name,
    maxCapacity,
    template: String(request.data?.template ?? ""),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: uid,
  }, { merge: true });
  return { success: true };
});

export const deleteItem = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const itemId = String(request.data?.itemId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !itemId) {
    throw new HttpsError("invalid-argument", "tenantId와 itemId가 필요합니다.");
  }
  await requireItemManagementAccess(
    uid,
    tenantId,
    String(request.data?.sourceDeviceId ?? ""),
  );
  await db.doc(`tenants/${tenantId}/items/${itemId}`).delete();
  return { success: true };
});

export const createTenantInvite = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const email = String(request.data?.email ?? "").trim().toLowerCase();
  const role = String(request.data?.role ?? "viewer") as Role;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !email || !["owner", "manager", "viewer", "botDevice"].includes(role)) {
    throw new HttpsError("invalid-argument", "유효한 초대 정보가 필요합니다.");
  }
  await requireMembership(uid, tenantId, ["owner"]);

  const tenant = await db.doc(`tenants/${tenantId}`).get();
  const inviteId = randomUUID();
  await db.doc(`tenantInvites/${inviteId}`).create({
    tenantId,
    tenantName: String(tenant.get("name") ?? ""),
    email,
    role,
    status: "pending",
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)),
  });
  return { inviteId, expiresInDays: 7 };
});

export const acceptTenantInvite = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const email = String(request.auth?.token.email ?? "").trim().toLowerCase();
  const inviteId = String(request.data?.inviteId ?? "").trim();
  if (!uid || !email) throw new HttpsError("unauthenticated", "이메일 로그인이 필요합니다.");
  if (!inviteId) throw new HttpsError("invalid-argument", "초대 코드가 필요합니다.");

  const inviteRef = db.doc(`tenantInvites/${inviteId}`);
  await db.runTransaction(async (transaction) => {
    const invite = await transaction.get(inviteRef);
    if (!invite.exists || invite.get("status") !== "pending") {
      throw new HttpsError("not-found", "유효한 초대가 아닙니다.");
    }
    if (invite.get("email") !== email) {
      throw new HttpsError("permission-denied", "초대받은 이메일과 로그인 이메일이 다릅니다.");
    }
    const expiresAt = invite.get("expiresAt") as Timestamp | undefined;
    if (!expiresAt || expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "초대가 만료되었습니다.");
    }
    const tenantId = String(invite.get("tenantId") ?? "");
    const tenant = await transaction.get(db.doc(`tenants/${tenantId}`));
    if (!tenant.exists || tenant.get("status") !== "active") {
      throw new HttpsError("failed-precondition", "현재 이용할 수 없는 가게입니다.");
    }
    const membership = {
      tenantId,
      tenantName: String(invite.get("tenantName") ?? tenant.get("name") ?? ""),
      role: String(invite.get("role") ?? "viewer"),
      status: "active",
      joinedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(db.doc(`tenants/${tenantId}/members/${uid}`), {
      email,
      role: membership.role,
      status: "active",
      joinedAt: FieldValue.serverTimestamp(),
      invitedBy: invite.get("createdBy"),
    }, { merge: true });
    transaction.set(db.doc(`users/${uid}/tenantMemberships/${tenantId}`), membership, {
      merge: true,
    });
    transaction.update(inviteRef, {
      status: "accepted",
      acceptedBy: uid,
      acceptedAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

export const listTenantInvites = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId) throw new HttpsError("invalid-argument", "tenantId가 필요합니다.");
  await requireMembership(uid, tenantId, ["owner"]);

  const invites = await db.collection("tenantInvites")
    .where("tenantId", "==", tenantId)
    .where("status", "==", "pending")
    .get();
  return {
    invites: invites.docs.map((invite) => ({
      inviteId: invite.id,
      email: String(invite.get("email") ?? ""),
      role: String(invite.get("role") ?? "viewer"),
      expiresAt: (invite.get("expiresAt") as Timestamp | undefined)?.toMillis() ?? 0,
    })),
  };
});

export const revokeTenantInvite = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const inviteId = String(request.data?.inviteId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !inviteId) {
    throw new HttpsError("invalid-argument", "tenantId와 inviteId가 필요합니다.");
  }
  await requireMembership(uid, tenantId, ["owner"]);
  const inviteRef = db.doc(`tenantInvites/${inviteId}`);
  const invite = await inviteRef.get();
  if (!invite.exists || invite.get("tenantId") !== tenantId) {
    throw new HttpsError("not-found", "초대를 찾을 수 없습니다.");
  }
  await inviteRef.set({
    status: "revoked",
    revokedBy: uid,
    revokedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true };
});

export const getBotSnapshot = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !deviceId) {
    throw new HttpsError("invalid-argument", "tenantId와 deviceId가 필요합니다.");
  }
  await requireActiveBotDevice(uid, tenantId, deviceId);

  const [items, reservations, rooms, botSettings] = await Promise.all([
    db.collection(`tenants/${tenantId}/items`).get(),
    db.collection(`tenants/${tenantId}/currentReservations`).get(),
    db.collection(`tenants/${tenantId}/rooms`).get(),
    db.doc(`tenants/${tenantId}/settings/bot`).get(),
  ]);
  return {
    items: items.docs.map((doc) => ({
      itemId: doc.id,
      name: String(doc.get("name") ?? ""),
      maxCapacity: Number(doc.get("maxCapacity") ?? 0),
      template: String(doc.get("template") ?? ""),
    })),
    reservations: reservations.docs.map((doc) => ({
      reservationId: doc.id,
      itemId: String(doc.get("itemId") ?? ""),
      nickname: String(doc.get("nickname") ?? ""),
      roomName: String(doc.get("roomName") ?? ""),
      createdAt: doc.get("createdAt")?.toDate?.()?.toISOString?.() ?? "",
    })),
    rooms: rooms.docs.map((doc) => ({
      name: String(doc.get("name") ?? ""),
      type: String(doc.get("type") ?? "general"),
    })),
    settings: botSettings.exists ? botSettings.data() : {},
  };
});

export const updateBotSettings = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const deviceId = String(request.data?.deviceId ?? "");
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !deviceId) {
    throw new HttpsError("invalid-argument", "tenantId와 deviceId가 필요합니다.");
  }
  await requireActiveBotDevice(uid, tenantId, deviceId);

  const commands = request.data?.commands ?? {};
  const settings: Record<string, unknown> = {
    commands: {
      reserve: String(commands.reserve ?? "예약").slice(0, 50),
      cancel: String(commands.cancel ?? "예약취소").slice(0, 50),
      status: String(commands.status ?? "조회").slice(0, 50),
      reset: String(commands.reset ?? "초기화").slice(0, 50),
      max: String(commands.max ?? "세팅최대").slice(0, 50),
      template: String(commands.template ?? "텍스트변경").slice(0, 50),
      total: String(commands.total ?? "전체조회").slice(0, 50),
    },
    totalTemplate: String(request.data?.totalTemplate ?? "").slice(0, 5000),
    resetHour: Math.max(0, Math.min(23, Number(request.data?.resetHour ?? 0))),
    resetMinute: Math.max(0, Math.min(59, Number(request.data?.resetMinute ?? 0))),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: uid,
  };
  await db.doc(`tenants/${tenantId}/settings/bot`).set(settings, { merge: true });

  const rooms = Array.isArray(request.data?.rooms) ? request.data.rooms : [];
  const existingRooms = await db.collection(`tenants/${tenantId}/rooms`).get();
  const desiredRoomIds = new Set<string>();
  const writer = db.bulkWriter();
  for (const room of rooms.slice(0, 500)) {
    const name = String(room?.name ?? "").trim();
    const type = String(room?.type ?? "general");
    if (!name || name.length > 200 || !["reservation", "admin", "general"].includes(type)) {
      continue;
    }
    const roomId = Buffer.from(name, "utf8").toString("base64url").slice(0, 500);
    desiredRoomIds.add(roomId);
    writer.set(db.doc(`tenants/${tenantId}/rooms/${roomId}`), {
      name,
      type,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: uid,
    }, { merge: true });
  }
  for (const room of existingRooms.docs) {
    if (!desiredRoomIds.has(room.id)) writer.delete(room.ref);
  }
  await writer.close();
  return { success: true };
});

export const createReservationEvent = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  const tenantId = String(request.data?.tenantId ?? "");
  const eventId = String(request.data?.eventId ?? "");
  const reservationId = String(request.data?.reservationId ?? "");
  const type = String(request.data?.type ?? "created");
  const itemId = String(request.data?.itemId ?? "");
  const businessDate = String(request.data?.businessDate ?? "");
  const allowedTypes = ["created", "updated", "cancelled", "reset"];

  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  if (!tenantId || !eventId || !reservationId) {
    throw new HttpsError("invalid-argument", "필수 예약 식별자가 없습니다.");
  }
  if (!allowedTypes.includes(type)) {
    throw new HttpsError("invalid-argument", "지원하지 않는 예약 이벤트입니다.");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(businessDate) || !itemId) {
    throw new HttpsError("invalid-argument", "유효한 항목과 영업일이 필요합니다.");
  }
  for (const value of [
    eventId,
    reservationId,
    itemId,
    request.data?.itemName,
    request.data?.nickname,
    request.data?.roomName,
  ]) {
    if (String(value ?? "").length > 200) {
      throw new HttpsError("invalid-argument", "예약 입력값이 너무 깁니다.");
    }
  }
  const member = await requireMembership(
    uid,
    tenantId,
    ["owner", "manager", "botDevice"],
  );
  const sourceDeviceId = String(request.data?.sourceDeviceId ?? "");
  if (sourceDeviceId === "admin") {
    if (!["owner", "manager"].includes(member.get("role") as Role)) {
      throw new HttpsError("permission-denied", "관리자 예약 권한이 없습니다.");
    }
  } else {
    const tenant = await db.doc(`tenants/${tenantId}`).get();
    const device = await db.doc(`tenants/${tenantId}/devices/${sourceDeviceId}`).get();
    if (
      !sourceDeviceId
      || tenant.get("activeBotDeviceId") !== sourceDeviceId
      || !device.exists
      || device.get("status") !== "active"
      || device.get("mode") !== "bot"
      || device.get("uid") !== uid
    ) {
      throw new HttpsError("permission-denied", "활성 예약봇 기기가 아닙니다.");
    }
  }

  const eventRef = db.doc(`tenants/${tenantId}/reservationEvents/${eventId}`);
  const reservationRef = db.doc(
    `tenants/${tenantId}/currentReservations/${reservationId}`,
  );
  await db.runTransaction(async (transaction) => {
    const eventSnapshot = await transaction.get(eventRef);
    if (eventSnapshot.exists) return;
    const reservationSnapshot = await transaction.get(reservationRef);

    if (type === "created" || type === "updated") {
      if (reservationSnapshot.exists) {
        if (type === "created") return;
      } else if (type === "updated") {
        throw new HttpsError("not-found", "수정할 예약이 존재하지 않습니다.");
      }
      const nickname = String(request.data?.nickname ?? "").trim();
      if (!nickname) {
        throw new HttpsError("invalid-argument", "예약자 이름이 필요합니다.");
      }
      const item = await transaction.get(db.doc(`tenants/${tenantId}/items/${itemId}`));
      if (!item.exists) {
        throw new HttpsError("not-found", "예약 항목이 존재하지 않습니다.");
      }
      const currentReservations = await transaction.get(
        db.collection(`tenants/${tenantId}/currentReservations`)
          .where("itemId", "==", itemId)
          .where("businessDate", "==", businessDate),
      );
      const movingToAnotherItem = type === "updated"
        && reservationSnapshot.get("itemId") !== itemId;
      if (
        currentReservations.size >= Number(item.get("maxCapacity") ?? 0)
        && (type === "created" || movingToAnotherItem)
      ) {
        throw new HttpsError("resource-exhausted", "예약 정원이 가득 찼습니다.");
      }
      if (currentReservations.docs.some(
        (doc) => doc.id !== reservationId && doc.get("nickname") === nickname,
      )) {
        throw new HttpsError("already-exists", "이미 예약된 이름입니다.");
      }
    } else if (type === "cancelled" && !reservationSnapshot.exists) {
      throw new HttpsError("not-found", "취소할 예약이 존재하지 않습니다.");
    }

    const effectiveItemId = type === "cancelled"
      ? String(reservationSnapshot.get("itemId") ?? "")
      : itemId;
    const effectiveItemName = type === "cancelled"
      ? String(reservationSnapshot.get("itemName") ?? "")
      : String(request.data?.itemName ?? "").trim();
    const effectiveNickname = type === "cancelled"
      ? String(reservationSnapshot.get("nickname") ?? "")
      : String(request.data?.nickname ?? "").trim();
    const effectiveRoomName = type === "cancelled"
      ? String(reservationSnapshot.get("roomName") ?? "")
      : String(request.data?.roomName ?? "").trim();
    const effectiveBusinessDate = type === "cancelled"
      ? String(reservationSnapshot.get("businessDate") ?? "")
      : businessDate;

    transaction.create(eventRef, {
      eventId,
      reservationId,
      type,
      itemId: effectiveItemId,
      itemName: effectiveItemName,
      nickname: effectiveNickname,
      roomName: effectiveRoomName,
      businessDate: effectiveBusinessDate,
      sourceDeviceId,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
    });

    if (type === "created" || type === "updated") {
      transaction.set(reservationRef, {
        reservationId,
        itemId,
        itemName: String(request.data?.itemName ?? "").trim(),
        nickname: String(request.data?.nickname ?? "").trim(),
        roomName: String(request.data?.roomName ?? "").trim(),
        businessDate,
        sourceDeviceId,
        createdBy: uid,
        ...(type === "created" ? { createdAt: FieldValue.serverTimestamp() } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: type === "updated" });
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
    if (reservations.size > 0) {
      await db.doc(`tenants/${tenantId}/dailyStats/${businessDate}`).set({
        activeDelta: FieldValue.increment(-reservations.size),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
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
    } else if (data.type === "updated") {
      updates.updatedCount = FieldValue.increment(1);
    } else if (data.type === "cancelled") {
      updates.cancelledCount = FieldValue.increment(1);
      updates.activeDelta = FieldValue.increment(-1);
    } else if (data.type === "reset") {
      updates.resetCount = FieldValue.increment(1);
    }
    await statsRef.set(updates, { merge: true });
  },
);
