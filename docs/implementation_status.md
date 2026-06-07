# 클라우드 전환 구현 현황

## 현재 구현됨

- Firebase Auth 이메일 로그인 및 계정 생성 화면
- 로그인 후 가게 선택 및 첫 가게 생성
- 예약봇 모드 / 관리자 모드 선택
- 예약봇 모드에서만 Android 알림 리스너와 포그라운드 서비스 활성화
- 관리자 모드 FCM 토큰 등록 및 예약 푸시 수신 기반
- 예약 생성, 취소, 초기화 이벤트 Cloud Functions 업로드
- 네트워크 장애 시 SQLite 영구 동기화 큐 저장 및 재전송
- 관리자 모드 Firestore 실시간 예약 이벤트 조회
- 관리자 모드 현재 예약 현황 조회
- 관리자 직접 예약 추가 및 취소
- owner의 테넌트 멤버 추가, 제거, 역할 지정
- 예약 이벤트 기반 일별 예약·취소 통계 집계
- 관리자 최근 30일 분석 화면
- Firestore 멀티테넌트 데이터 구조와 Security Rules
- 가게 생성, 기기 등록/해제, 예약 이벤트 생성, 관리자 푸시 Cloud Functions
- Firebase Emulator 설정

## 아직 필요한 작업

- Firebase Console에서 이메일/비밀번호 Authentication 활성화
- Firestore Database 생성
- Blaze 요금제 활성화 후 Functions 배포
- 만료된 Firebase CLI 로그인 갱신
- 기존 SQLite 데이터의 서버 마이그레이션
- 기존 SQLite 데이터의 최초 서버 업로드
- 관리자 예약 수정 UI
- 항목별, 시간대별 상세 분석 대시보드
- 플랫폼 운영자용 웹 관리 콘솔
- 가입 전 사용자를 위한 이메일 초대 링크
- App Check와 운영 보안 강화

## 배포 명령

Firebase CLI 로그인 후 프로젝트 루트에서 실행한다.

```powershell
firebase login --reauth
firebase use releasenote-80bf5
firebase deploy --only firestore:rules,firestore:indexes,functions
```

현재 Firebase CLI 인증 토큰이 만료되어 자동 배포는 완료하지 못했다.
