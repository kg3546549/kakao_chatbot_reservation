# 2026-06-12 브랜딩 및 기기 반영 정리

## 변경 목적

- 예전 업장 브랜딩 흔적 제거
- 앱 이름을 `모두예약`으로 통일
- 새 로고를 앱 자산, 런처 아이콘, 스플래시에 반영
- 앱 전반 배경색을 `#FEFEFE`로 통일
- 가게 목록 로딩 시 일부 권한 불일치 문서 때문에 전체 목록이 실패하는 문제 완화

## 적용 내용

### 1. 브랜딩 정리

- 앱 이름을 `모두예약`으로 변경
- 로그인 화면 제목, Android 앱 라벨, 알림 리스너 라벨 정리
- 코드와 문서에서 `하이잭`, `홀덤`, `메인/무토` 예시 문구 제거 또는 일반화

### 2. 로고 및 아이콘 반영

- 새 로고를 `assets/logo.png`, `logo.png`에 반영
- 원본 보관용 파일을 `assets/logo-generated-v1.png`로 추가
- `flutter_launcher_icons`로 Android 런처 아이콘 재생성
- adaptive icon background를 `#FEFEFE`로 통일
- Android 12+ 스플래시와 구버전 스플래시 모두 새 로고/배경색 적용

### 3. 배경색 통일

- 공통 테마의 `surface`, `scaffoldBackgroundColor`, `AppBar`, `NavigationBar`를 `#FEFEFE`로 조정
- 개별 화면에서 남아 있던 `#F8F9FA` 또는 `Colors.white` 기반 배경 일부를 `#FEFEFE`로 정리

### 4. 권한 오류 완화

- `SessionProvider`의 가게 목록 로딩 로직을 수정
- `users/{uid}/tenantMemberships`는 남아 있지만 실제 tenant 문서 접근 권한이 없는 경우:
  - 전체 목록 실패 대신 해당 가게만 건너뜀
  - 사용자에게 경고 메시지를 표시

## 검증 내역

- `flutter analyze` 통과
- Android debug APK 빌드 및 연결 기기 `SM A346N` 재설치/실행 확인
- 발표자료 `presentation.pptx` 재생성

## 남은 이슈

### Firebase App Check

디버그 실행 로그에서 아래 오류가 계속 확인됨.

- `App Check token refresh failed`
- `403 App attestation failed`

이 문제는 Firestore/Functions 접근 실패와 별도로 존재하며, 디버그 기기 등록 또는 App Check 정책 조정이 필요하다.

### release APK 서명

로컬 환경에서 release APK 직접 설치 시 인증서 수집 오류가 발생했다.

- `INSTALL_PARSE_FAILED_NO_CERTIFICATES`

debug APK 기준으로는 설치와 실행을 확인했다.
