# 클라우드 전환 구현 현황

## 현재 구현됨

- Firebase Auth 이메일 로그인 및 계정 생성 화면
- 로그인 후 가게 선택 및 첫 가게 생성
- 예약봇 모드 / 관리자 모드 선택
- 예약봇 모드에서만 Android 알림 리스너와 포그라운드 서비스 활성화
- 관리자 모드 FCM 토큰 등록 및 예약 푸시 수신 기반
- 예약 생성, 수정, 취소, 초기화 이벤트 Cloud Functions 업로드
- 서버 예약 생성·수정 시 항목, 정원, 중복 이름, 상태 전이 검증
- 네트워크 장애 시 테넌트별 SQLite 영구 동기화 큐 저장 및 지수 백오프 재전송
- 관리자 모드 Firestore 실시간 예약 이벤트 조회
- 관리자 모드 현재 예약 현황 조회
- 관리자 직접 예약 추가, 수정 및 취소
- owner의 테넌트 멤버 추가, 제거, 역할 지정
- 예약 이벤트 기반 일별 예약·취소 통계 집계
- 관리자 최근 30일 분석 화면
- 최근 예약 이벤트 기반 항목별·시간대별 상세 분석
- 테넌트당 활성 예약봇 기기 1대 제한 및 원격 연결 해제
- 예약봇 기존 항목과 예약의 멱등 서버 최초 업로드
- 빈 새 예약봇 기기의 서버 항목·현재 예약 자동 복원과 서버 예약 ID 유지
- SQLite 항목, 방, 예약, 로그, 동기화 큐의 테넌트별 격리와 기존 데이터 마이그레이션
- 봇 예약 시 로컬 정원 및 중복 이름 검증
- 카카오톡 관리자 명령으로 변경한 항목의 서버 동기화
- 관리자 항목 현황 조회
- 테넌트 데이터 격리 Firestore Rules 자동 테스트
- 앱 재시작 후 마지막 테넌트와 모드 자동 복원
- Firestore 멀티테넌트 데이터 구조와 Security Rules
- 가게 생성, 기기 등록/해제, 예약 이벤트 생성, 관리자 푸시 Cloud Functions
- Firebase Emulator 설정
- 전경·백그라운드·종료 상태 FCM 알림 클릭 시 관리자 루트 화면 복귀
- App Check 클라이언트 초기화: 디버그 공급자 / 릴리스 Play Integrity
- App Check 디버그 토큰 등록 및 Auth, Firestore, Callable Functions 검증 강제
- 실제 Firebase Android 앱 등록 및 `google-services.json` 적용
- Firebase Authentication 이메일/비밀번호 활성화
- Firestore Rules, Indexes 및 Cloud Functions 19개 운영 배포
- Artifact Registry 1일 이미지 정리 정책 적용
- 예약봇 설정의 동기화 대기·실패 이벤트 조회 및 개별·전체 수동 재처리
- 방 유형, 명령어, 전체 템플릿, 예약 기준 시간의 서버 백업·복원
- 로그인 이메일에 귀속된 7일 초대 코드 생성, 직접 전달 및 로그인 후 수락
- owner의 대기 초대 목록 조회 및 초대 취소
- 새 가게 생성의 플랫폼 운영자 권한 제한

## 아직 필요한 작업

- Firebase App Check 강제 적용 후 거부율과 정상 요청 운영 모니터링
- 실제 운영 계정 생성, 최초 플랫폼 관리자 설정 및 가게 생성
- 서버 항목 ID의 UUID 전환과 숫자형 기존 항목 ID 마이그레이션
- 여러 봇 기기 간 설정 변경 충돌 정책과 설정 변경 이력
- 분석 집계의 기간 필터, 차트 시각화 및 대용량 집계 최적화
- 플랫폼 운영자용 웹 관리 콘솔
- 초대 코드 재발급
- Firebase Authentication 자체의 임의 계정 생성 제한 또는 승인 대기 정책
- Functions 통합 테스트와 실기기 예약·푸시 E2E 테스트
- Functions 운영 의존성 보안 업데이트

## 배포 명령

Firebase CLI 로그인 후 프로젝트 루트에서 실행한다.

```powershell
firebase login --reauth
firebase use releasenote-80bf5
firebase deploy --only firestore:rules,firestore:indexes,functions
```

로컬 Firebase Emulator는 Java 21 이상이 필요하다. Android 빌드 전에는
`android/app/google-services.json`을 배치해야 한다.

Firebase CLI 로그인과 운영 프로젝트 배포는 완료되었다.
