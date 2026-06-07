import fs from "node:fs";
import test, { after, before } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

const projectId = "demo-kakao-reservation-rules";
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync("../firestore.rules", "utf8"),
    },
  });

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "tenants/tenant-a"), {
      name: "가게 A",
      status: "active",
    });
    await setDoc(doc(db, "tenants/tenant-a/members/user-a"), {
      role: "manager",
      status: "active",
    });
    await setDoc(doc(db, "tenants/tenant-a/currentReservations/reservation-a"), {
      nickname: "예약자",
    });
    await setDoc(doc(db, "tenants/tenant-b"), {
      name: "가게 B",
      status: "suspended",
    });
    await setDoc(doc(db, "tenants/tenant-b/members/user-b"), {
      role: "owner",
      status: "active",
    });
    await setDoc(doc(db, "tenants/tenant-b/currentReservations/reservation-b"), {
      nickname: "정지 가게 예약자",
    });
  });
});

after(async () => {
  await env.cleanup();
});

test("active tenant member can read its reservations", async () => {
  const db = env.authenticatedContext("user-a").firestore();
  await assertSucceeds(
    getDoc(doc(db, "tenants/tenant-a/currentReservations/reservation-a")),
  );
});

test("member cannot read another tenant reservations", async () => {
  const db = env.authenticatedContext("user-a").firestore();
  await assertFails(
    getDoc(doc(db, "tenants/tenant-b/currentReservations/reservation-b")),
  );
});

test("suspended tenant member cannot read tenant reservations", async () => {
  const db = env.authenticatedContext("user-b").firestore();
  await assertFails(
    getDoc(doc(db, "tenants/tenant-b/currentReservations/reservation-b")),
  );
});

test("platform admin can read suspended tenant document", async () => {
  const db = env.authenticatedContext("platform-admin", {
    platformAdmin: true,
  }).firestore();
  await assertSucceeds(getDoc(doc(db, "tenants/tenant-b")));
});
