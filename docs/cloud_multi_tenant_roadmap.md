# 카카오톡 예약 관리 플랫폼 전환 계획

## 1. 문서 목적

현재 Android 로컬 예약봇 앱을 다음 형태의 클라우드 기반 멀티테넌트 서비스로 전환한다.

- 한 앱에서 로그인 후 `예약봇 모드` 또는 `관리자 모드`로 동작
- 예약봇 기기에서 수집된 예약을 서버에 저장
- 여러 관리자 기기에서 현재 예약 현황, 이력, 분석 대시보드를 실시간 조회
- 예약 생성 및 변경 시 관리자 기기에 푸시 알림 전송
- 여러 가게의 데이터와 사용자를 테넌트별로 완전히 분리
- 플랫폼 운영자가 가게, 사용자, 기기, 사용 상태를 관리하는 웹 관리 콘솔 제공

이 문서는 앞으로 구현해야 할 범위와 권장 순서를 정의한다.

---

## 2. 현재 상태

현재 앱의 핵심 데이터와 기능은 기기 내부에 있다.

| 영역 | 현재 구현 |
|---|---|
| 예약, 항목, 방, 로그 | SQLite |
| 명령어 및 초기화 시간 | SharedPreferences |
| 카카오톡 메시지 수신 | Android NotificationListenerService |
| 카카오톡 자동 답장 | 알림 RemoteInput 액션 |
| 백그라운드 유지 | ForegroundKeepAliveService |
| 오류 및 사용 로그 | Firebase Crashlytics, Analytics |
| 로그인 및 권한 | 없음 |
| 서버 데이터 동기화 | 없음 |
| 멀티테넌트 | 없음 |
| 관리자 푸시 | 없음 |

현재 `items`, `rooms`, `reservations`의 ID가 로컬 정수이므로 여러 기기와 서버에서 공유할 수 없다. 서버 전환 전에 UUID 기반 식별자와 테넌트 ID를 도입해야 한다.

---

## 3. 제품 방향 및 용어 정리

### 3.1 제품 명칭

사용자에게 노출되는 제품 명칭과 설명을 `카카오톡 예약 관리` 중심으로 통일한다.

제거 또는 변경 대상:

- 하이잭, 탈취, 가로채기 등 오해를 유발할 수 있는 표현
- 개발용 명칭과 임시 설명
- `A new Flutter project` 같은 기본 텍스트
- 사용자 화면에 노출되는 기술 용어

권장 사용자 용어:

- `예약봇 기기`
- `카카오톡 예약 연동`
- `예약 메시지 감지`
- `자동 응답`
- `관리자 대시보드`

### 3.2 알림 접근 기능에 대한 결정 필요

현재 자동 예약 수신과 답장은 Android 알림 접근 권한과 RemoteInput에 의존한다. 이 기능 자체를 제거하면 현재 방식의 카카오톡 자동 예약봇 기능도 동작하지 않는다.

따라서 다음 중 하나를 제품 정책으로 선택해야 한다.

| 선택안 | 설명 | 영향 |
|---|---|---|
| A. 기술 유지, 표현만 정리 | 예약봇 모드에서만 알림 접근 기능 사용 | 기존 자동 예약 기능 유지 가능 |
| B. 알림 접근 기능 완전 제거 | 공식 카카오 채널/챗봇 연동 등 다른 입력 경로 사용 | 서버 연동 방식과 카카오 계약/설정 필요 |

초기 권장안은 **A안**이다. 관리자 모드에서는 알림 접근 권한과 포그라운드 서비스를 완전히 비활성화하고, 예약봇 모드에서만 명시적 동의를 받은 뒤 사용한다.

---

## 4. 목표 사용자와 역할

### 4.1 플랫폼 역할

| 역할 | 설명 | 주요 권한 |
|---|---|---|
| platformAdmin | 전체 서비스를 운영하는 내부 관리자 | 모든 테넌트 생성, 정지, 사용자 및 기기 관리 |
| tenantOwner | 가게 대표 관리자 | 해당 가게 설정, 멤버 초대, 전체 데이터 관리 |
| tenantManager | 가게 관리자 | 예약 관리, 대시보드 및 이력 조회 |
| botDevice | 예약봇으로 승인된 기기 | 예약 이벤트 생성 및 자동 응답 |
| viewer | 조회 전용 사용자 | 현황, 이력, 통계 조회 |

### 4.2 앱 모드

로그인 후 사용자가 접근 가능한 테넌트와 역할을 확인하고 모드를 선택한다.

#### 예약봇 모드

- Android 전용
- 알림 접근 권한과 배터리 최적화 제외 권한 요청
- 포그라운드 서비스 실행
- 카카오톡 메시지에서 예약 명령 처리
- 로컬 우선 저장 후 서버 동기화
- 조직당 활성 예약봇 기기 수 제한

#### 관리자 모드

- 알림 접근 권한 요청 안 함
- 포그라운드 KeepAlive 서비스 실행 안 함
- Firestore 실시간 데이터 조회
- 예약 생성, 수정, 취소 및 승인
- 예약 발생 시 FCM 푸시 수신
- 이력 및 분석 대시보드 조회

모드는 단순 화면 토글이 아니라 Android 서비스 실행 여부와 서버 권한을 함께 제어해야 한다.

---

## 5. 권장 시스템 구조

```text
예약봇 모드 앱
  -> 로컬 SQLite 저장
  -> Callable Cloud Function으로 예약 이벤트 전송
  -> Firestore에 테넌트별 저장
  -> Firestore Trigger Function 실행
  -> 관리자 기기에 FCM 푸시

관리자 모드 앱 / 운영 웹 콘솔
  -> Firebase Authentication 로그인
  -> Firestore 실시간 구독
  -> 예약 현황, 이력, 통계 조회
```

### 5.1 Firebase 서비스 역할

| Firebase 서비스 | 역할 |
|---|---|
| Firebase Authentication | 이메일/비밀번호 또는 Google 로그인 |
| Cloud Firestore | 테넌트, 멤버, 항목, 예약 이벤트, 집계 데이터 저장 |
| Cloud Functions | 권한 검증, 예약 변경, 중복 방지, 집계, 푸시 발송 |
| Firebase Cloud Messaging | 관리자 예약 푸시 |
| Firebase App Check | 허가되지 않은 클라이언트 요청 차단 |
| Firebase Hosting | 플랫폼 운영자용 웹 관리 콘솔 배포 |
| Crashlytics / Analytics | 오류 및 사용 현황 추적 |

Cloud Functions 사용과 운영 배포를 위해 Blaze 요금제가 필요하다.

---

## 6. 멀티테넌트 설계

### 6.1 권장 방식

초기 버전은 Firebase Authentication 계정을 공통으로 사용하고, Firestore 문서 경로에서 가게 데이터를 분리한다.

```text
tenants/{tenantId}
tenants/{tenantId}/members/{uid}
tenants/{tenantId}/devices/{deviceId}
tenants/{tenantId}/items/{itemId}
tenants/{tenantId}/rooms/{roomId}
tenants/{tenantId}/reservationEvents/{eventId}
tenants/{tenantId}/dailyStats/{businessDate}
users/{uid}
users/{uid}/tenantMemberships/{tenantId}
```

모든 업무 데이터에는 `tenantId`가 포함되어야 하며, Security Rules와 Cloud Functions에서 접근 권한을 검증한다.

### 6.2 Firebase Authentication의 공식 멀티테넌시

Firebase Authentication with Identity Platform은 하나의 프로젝트 안에서 사용자와 로그인 설정을 tenant 단위로 분리할 수 있다. 하지만 이것은 **가게 관리 페이지나 업무 데이터 분리 기능이 아니라 로그인 계정 저장소 분리 기능**이다.

초기 서비스에는 과도한 복잡성이 있으므로 바로 사용하지 않는 것을 권장한다. 다음 요구가 생길 때 도입을 검토한다.

- 가게마다 서로 다른 로그인 제공자 또는 인증 정책 필요
- 동일 이메일이 가게마다 별도 계정이어야 함
- 엔터프라이즈 수준의 인증 격리 요구

### 6.3 Custom Claims 사용 범위

Custom Claims는 `platformAdmin` 같은 전역 권한만 저장한다. 테넌트 목록이나 상세 설정은 Claims에 넣지 않고 Firestore membership 문서에 저장한다.

이유:

- Claims는 서버 Admin SDK에서만 안전하게 변경해야 함
- 토큰 갱신 전까지 변경 내용이 즉시 반영되지 않음
- Claims 크기 제한이 있어 여러 테넌트 정보를 넣기에 부적합

---

## 7. Firebase 기본 관리 기능으로 가능한 범위

### 7.1 Firebase Console에서 가능한 것

- Authentication 사용자 조회 및 비활성화
- Firestore 문서 직접 조회 및 수정
- Functions 실행 상태와 로그 확인
- FCM 알림 테스트
- Crashlytics 오류 확인
- Analytics 사용 현황 확인

### 7.2 Firebase Console만으로 부족한 것

- 가게 생성 및 정지 워크플로
- 가게 대표와 관리자 초대
- 가게별 예약 현황 및 분석 화면
- 가게별 사용량과 요금제 관리
- 봇 기기 승인 및 해제
- 운영자 감사 로그

Firebase Console은 개발자용 운영 도구이며 가게 관리자에게 제공할 관리 화면으로 사용하면 안 된다. Firestore 원본 데이터와 전체 프로젝트 설정에 접근하게 되기 때문이다.

### 7.3 권장 관리 페이지

Flutter Web 또는 별도 웹 프론트엔드로 `플랫폼 운영 콘솔`을 만들고 Firebase Hosting에 배포한다.

최소 기능:

- 전체 테넌트 목록, 생성, 수정, 활성/정지
- 테넌트별 owner 지정 및 멤버 관리
- 봇 기기 승인, 해제, 마지막 접속 시각 확인
- 테넌트별 예약 수, 활성 사용자 수, 오류 현황
- 운영자 감사 로그
- 필요 시 사용자 계정 비활성화

관리 작업은 클라이언트에서 Firestore를 직접 수정하지 않고, `platformAdmin` 권한을 검증하는 Callable Cloud Functions를 통해 수행한다.

---

## 8. 서버 데이터 모델

### 8.1 Tenant

```json
{
  "name": "강남점",
  "status": "active",
  "timezone": "Asia/Seoul",
  "createdAt": "serverTimestamp",
  "createdBy": "uid"
}
```

### 8.2 Membership

```json
{
  "role": "owner",
  "status": "active",
  "joinedAt": "serverTimestamp"
}
```

### 8.3 Device

```json
{
  "mode": "bot",
  "name": "강남점 예약봇",
  "status": "approved",
  "fcmToken": "...",
  "lastSeenAt": "serverTimestamp",
  "appVersion": "1.0.0"
}
```

### 8.4 Reservation Event

예약을 현재 상태 문서만으로 관리하지 않고 변경 이벤트를 보존한다.

```json
{
  "eventId": "UUID",
  "type": "created",
  "reservationId": "UUID",
  "itemId": "UUID",
  "nickname": "홍길동",
  "roomName": "예약방",
  "businessDate": "2026-06-07",
  "sourceDeviceId": "UUID",
  "createdBy": "uid",
  "createdAt": "serverTimestamp"
}
```

이벤트 타입:

- `created`
- `cancelled`
- `reset`
- `updated`
- `approved`
- `rejected`

`eventId`를 Firestore 문서 ID로 사용해 네트워크 재시도 시 중복 저장을 방지한다.

---

## 9. 로그인 및 모드 선택 흐름

```text
앱 시작
  -> Firebase 초기화
  -> 로그인 상태 확인
  -> 미로그인: 로그인 화면
  -> 로그인: 접근 가능한 테넌트 조회
  -> 테넌트 선택
  -> 허용된 역할과 등록된 기기 확인
  -> 예약봇 모드 또는 관리자 모드 선택
  -> 선택 모드에 맞는 홈 화면과 서비스 시작
```

### 9.1 로그인 초기 범위

초기 버전은 이메일/비밀번호 로그인을 권장한다.

- 운영자가 대상 계정 이메일에 귀속된 초대 코드를 생성해 직접 전달
- 초대 이메일과 초대 링크는 발송하지 않음
- 임의 회원가입은 비활성화하거나 가입 후 승인 대기 처리
- 비밀번호 재설정 지원
- 추후 Google 로그인 추가 가능

### 9.2 모드 선택 정책

- `botDevice` 권한과 승인된 기기만 예약봇 모드 선택 가능
- 관리자 권한이 있는 사용자는 관리자 모드 선택 가능
- 마지막 선택 모드는 로컬에 저장하되, 앱 시작마다 서버 권한을 다시 검증
- 로그아웃 또는 테넌트 변경 시 포그라운드 서비스와 FCM 구독 정리

---

## 10. 관리자 모드 기능

### 10.1 예약 푸시

예약 이벤트가 생성되면 Cloud Function이 해당 테넌트의 활성 관리자 기기 FCM 토큰으로 푸시를 전송한다.

푸시 데이터:

```json
{
  "type": "reservation_created",
  "tenantId": "tenant-id",
  "reservationId": "reservation-id",
  "itemId": "item-id"
}
```

알림을 누르면 해당 예약 또는 당일 예약 현황 화면으로 이동한다.

토픽 구독은 구현이 간단하지만 테넌트 권한 변경 후 즉시 차단하기 어렵다. 운영 버전에서는 서버가 승인된 관리자 기기의 FCM 토큰을 조회해 직접 전송하는 방식을 권장한다.

### 10.2 예약 관리

- 오늘 및 날짜별 예약 현황 실시간 조회
- 예약 수동 추가, 수정, 취소
- 예약 승인 및 거절
- 항목별 정원 확인
- 검색 및 필터
- 변경 이력과 변경 사용자 표시

### 10.3 분석 대시보드

- 오늘 예약 수 및 취소 수
- 항목별 예약 비중과 점유율
- 일별, 주별, 월별 추이
- 자주 방문한 고객
- 예약 발생 시간대
- 노쇼 또는 승인 거절 통계
- 전일 및 전주 대비 증감

초기에는 원본 예약 이벤트를 조회해 계산하고, 데이터가 증가하면 Cloud Functions가 `dailyStats` 문서를 집계하도록 전환한다.

---

## 11. 로컬 데이터와 서버 동기화

예약봇 모드는 네트워크가 끊겨도 카카오톡 예약 처리를 계속해야 한다.

권장 처리 순서:

1. 예약 이벤트 UUID 생성
2. SQLite에 예약과 `pending_sync` 이벤트 저장
3. 카카오톡 답장 처리
4. Callable Function으로 이벤트 전송
5. 서버 성공 응답 후 `synced` 처리
6. 실패 시 지수 백오프로 재시도

Firestore 자체도 Android에서 오프라인 캐시와 쓰기 큐를 제공하지만, 카카오톡 자동 응답과 정확한 재처리 상태가 중요하므로 예약봇 모드의 SQLite 동기화 큐는 유지한다.

필수 동기화 상태:

- `pending`
- `syncing`
- `synced`
- `failed`

---

## 12. 보안 원칙

- 모든 데이터 요청은 로그인 사용자 기준으로 검증
- 모든 업무 데이터는 tenant 경로 아래 저장
- Firestore Security Rules에서 tenant membership 확인
- 예약 생성, 수정, 취소는 Callable Function을 통한 서버 검증 권장
- `platformAdmin` 권한은 Cloud Functions/Admin SDK에서만 설정
- 봇 기기는 서버 승인 후 이벤트 업로드 가능
- `google-services.json`은 서버 비밀키는 아니지만 저장소 정책을 정해 관리
- 서비스 계정 JSON과 FCM 서버 자격 증명은 앱과 Git에 절대 포함하지 않음
- App Check 적용
- 운영자 작업은 audit log로 기록

---

## 13. 코드 구조 변경안

현재 `BotProvider`와 `DatabaseService`에 업무 로직이 집중되어 있으므로 역할을 분리한다.

```text
lib/
  auth/
    auth_repository.dart
    session_provider.dart
  tenant/
    tenant_repository.dart
    tenant_provider.dart
  mode/
    app_mode.dart
    mode_provider.dart
  reservations/
    reservation_repository.dart
    local_reservation_repository.dart
    remote_reservation_repository.dart
    reservation_sync_service.dart
  notifications/
    push_notification_service.dart
  dashboard/
    dashboard_repository.dart
  ui/
    auth/
    mode_selection/
    bot/
    admin/
```

Android `ForegroundKeepAliveService`는 앱 시작 시 무조건 실행하지 않고, 로그인 완료 후 승인된 예약봇 모드일 때만 실행하도록 변경한다.

---

## 14. 단계별 구현 계획

### Phase 0. 정책 결정 및 제품 정리

- 알림 접근 기능 유지 여부 결정
- 제품명, 패키지명, 앱 아이콘, 설명 확정
- 사용자 노출 문구에서 하이잭 관련 표현 제거
- 테넌트 생성 주체와 가입 정책 결정
- 예약봇 기기 수 제한 정책 결정

완료 기준:

- 자동 예약 입력 경로와 운영 정책이 확정됨

### Phase 1. Firebase 서버 기반

- Firebase CLI 및 Functions 프로젝트 초기화
- Firestore, Functions, Auth, FCM 활성화
- Blaze 요금제 및 예산 알림 설정
- Firestore 데이터 모델과 Security Rules 작성
- Emulator Suite 기반 로컬 테스트 구성
- platformAdmin 초기 계정 구성

완료 기준:

- 테스트 테넌트와 사용자 권한이 서버에서 분리됨

### Phase 2. 로그인, 테넌트, 모드 선택

- Firebase Auth 이메일 로그인 구현
- 로그인 세션 및 로그아웃 구현
- 사용자 테넌트 목록 조회
- 테넌트 선택 화면 구현
- 예약봇/관리자 모드 선택 화면 구현
- 모드별 라우팅 및 Android 서비스 실행 제어

완료 기준:

- 권한 없는 사용자가 예약봇 모드를 실행할 수 없음

### Phase 3. 예약 서버 동기화

- 로컬 모델에 UUID, tenantId, syncStatus 추가
- SQLite 마이그레이션 구현
- 예약 생성, 취소, 초기화 Callable Functions 구현
- 로컬 동기화 큐 및 재시도 구현
- 서버 데이터 실시간 구독 구현
- 중복 이벤트 및 충돌 테스트

완료 기준:

- 예약봇 기기에서 발생한 예약을 다른 기기에서 조회 가능

### Phase 4. 관리자 모드

- 현재 예약 현황
- 예약 이력 및 검색
- 수동 예약 관리
- 항목과 정원 관리
- 관리자 권한별 UI와 서버 검증

완료 기준:

- 관리자 기기만으로 예약 운영이 가능

### Phase 5. 관리자 푸시

- `firebase_messaging` 연결
- 관리자 기기 등록 및 토큰 갱신
- 예약 생성/취소 Function 트리거
- FCM 발송 및 딥링크 처리
- 알림 권한과 전경/백그라운드/종료 상태 테스트

완료 기준:

- 예약 발생 후 승인된 관리자 기기에 푸시가 전달됨

### Phase 6. 분석 대시보드

- 일별 집계 Function 구현
- 테넌트별 통계 문서 생성
- 기간별 차트와 주요 지표 구현
- 데이터 보정 및 재집계 도구 구현

완료 기준:

- 원본 이벤트 전체 조회 없이 주요 대시보드 표시 가능

### Phase 7. 플랫폼 운영 웹 콘솔

- Firebase Hosting 기반 운영 콘솔 생성
- 테넌트 생성, 정지, 수정
- owner 및 멤버 관리
- 봇 기기 승인 및 상태 확인
- 테넌트 사용량 및 오류 현황
- 운영자 감사 로그

완료 기준:

- Firebase Console에서 Firestore 문서를 직접 수정하지 않고 운영 가능

### Phase 8. 운영 안정화

- App Check 적용
- Security Rules 및 Functions 테스트 강화
- Crashlytics, Functions 로그, 예산 알림 구성
- 백업 및 데이터 보존 정책 수립
- 개인정보 처리 및 사용자 동의 문구 정리
- 장애 대응 및 복구 절차 문서화

---

## 15. 우선순위 백로그

### 즉시 해야 할 작업

- 제품 정책상 알림 접근 기능 유지 여부 확정
- Firebase 프로젝트 Blaze 요금제 및 CLI 접근 준비
- `google-services.json` 저장소 포함 정책 결정
- Firebase Auth 로그인 제공자 결정
- 테넌트와 역할 모델 확정
- Firestore Security Rules 초안 작성

### MVP 필수

- 로그인
- 테넌트 선택
- 예약봇/관리자 모드 선택
- 예약 서버 동기화
- 관리자 실시간 현황과 이력
- 관리자 FCM 푸시
- 테넌트 데이터 접근 차단

### MVP 이후

- 분석 집계 고도화
- 플랫폼 운영 웹 콘솔
- 멤버 초대
- 사용량 및 과금 관리
- 공식 카카오 채널/챗봇 연동 검토

---

## 16. 주요 위험과 대응

| 위험 | 대응 |
|---|---|
| 알림 접근 기능 제거 시 자동 예약봇 기능 상실 | 공식 연동 대안 확정 전 기술 기능 제거 금지 |
| 동일 예약 이벤트 중복 업로드 | 클라이언트 UUID를 문서 ID로 사용 |
| 여러 봇 기기가 같은 메시지 처리 | tenant별 활성 botDevice lease 또는 단일 승인 정책 |
| 테넌트 간 데이터 노출 | Security Rules, Functions 검증, Emulator 테스트 |
| 관리자 권한 변경 후 기존 토큰 유지 | 서버 membership 검증, 필요 시 ID 토큰 강제 갱신 |
| 네트워크 장애 중 예약 유실 | SQLite 동기화 큐와 재시도 |
| FCM 토큰 노후화 | 토큰 갱신 저장 및 발송 실패 토큰 제거 |
| Firestore 비용 증가 | 집계 문서, 페이지네이션, 쿼리 인덱스, 예산 알림 |

---

## 17. 권장 최종 결정

1. 앱은 하나로 유지하고 로그인 후 예약봇 모드와 관리자 모드를 분리한다.
2. 초기 멀티테넌시는 Firestore 경로와 membership 문서로 구현한다.
3. Identity Platform 공식 멀티테넌시는 인증 격리가 실제로 필요할 때 도입한다.
4. Firebase Console은 내부 개발 운영에만 사용한다.
5. 여러 가게를 관리하는 플랫폼 운영 페이지는 Firebase Hosting 기반 웹 콘솔로 별도 구축한다.
6. 예약 변경은 이벤트 기반으로 저장하고 Cloud Functions에서 검증 및 푸시를 처리한다.
7. 예약봇 모드는 SQLite 로컬 우선 구조를 유지해 네트워크 장애에도 동작하게 한다.

---

## 18. 참고 공식 문서

- [Firebase Authentication](https://firebase.google.com/docs/auth)
- [Firebase Custom Claims](https://firebase.google.com/docs/auth/admin/custom-claims)
- [Firebase Security Rules 기본](https://firebase.google.com/docs/rules/basics)
- [Firestore Security Rules 조건](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [Firestore 오프라인 데이터](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Cloud Firestore 트리거](https://firebase.google.com/docs/functions/firestore-events)
- [Flutter FCM 메시지 수신](https://firebase.google.com/docs/cloud-messaging/flutter/receive)

