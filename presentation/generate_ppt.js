const pptxgen = require('pptxgenjs');

// PPTX 객체 생성
const pptx = new pptxgen();

// 16:9 레이아웃 설정 (10 x 5.625 인치 = 25.4 x 14.288 cm)
pptx.layout = 'LAYOUT_16x9';

// 공통 스타일 테마 정의 (HEX 코드에 '#' 제외)
const COLOR_PRIMARY = '40916C';   // 포레스트 그린 (주요 액센트)
const COLOR_SECONDARY = '2D6A4F'; // 짙은 포레스트 그린 (서브 액센트)
const COLOR_DARK = '1B4332';      // 매우 짙은 그린 (어두운 배경 및 중요 텍스트)
const COLOR_WHITE = 'FFFFFF';     // 카드 및 밝은 텍스트 배경
const COLOR_TEXT_DARK = '2D312E'; // 본문 어두운 텍스트
const COLOR_TEXT_MUTED = '6E7571';// 부가 설명 그레이 텍스트
const COLOR_ACCENT_RED = 'E63946';// 페인포인트 강조 레드
const COLOR_LIGHT_GREEN = 'D8F3DC';// 연한 연두색 (어두운 배경 위의 텍스트/도형용)
const COLOR_LIGHT_RED = 'FFEBEE';  // 페인포인트 카드 배경

const FONT_FAMILY = 'Pretendard';

// 슬라이드별 배경 설정 헬퍼 함수
function applySlideBackground(slide, isDark = false) {
  if (isDark) {
    // 어두운 슬라이드: 딥 에메랄드 -> 다크 포레스트 그라데이션
    slide.addShape(pptx.shapes.RECTANGLE, {
      x: 0, y: 0, w: 10.0, h: 5.625,
      fill: { type: 'gradient', color1: '1B4332', color2: '081F14', angle: 45 },
      line: { width: 0 }
    });
  } else {
    // 일반 슬라이드: 연한 파스텔 민트그린 -> 소프트 오프화이트 그라데이션
    slide.addShape(pptx.shapes.RECTANGLE, {
      x: 0, y: 0, w: 10.0, h: 5.625,
      fill: { type: 'gradient', color1: 'E8F2EC', color2: 'F5F8F6', angle: 135 },
      line: { width: 0 }
    });
  }
}

// 솔리드(Solid) 카드 생성 헬퍼 함수
function addCleanCard(slide, x, y, w, h, styleType = 'normal') {
  let fillColor = 'FFFFFF';
  let lineColor = 'E2E8F0';
  let lineWidth = 1;
  let lineTrans = 0;
  let fillTrans = 0;
  let shadowColor = '94A3B8';
  let shadowOpacity = 0.05;
  let shadowBlur = 6;
  let shadowOffset = 2;

  if (styleType === 'highlight') {
    fillColor = '2D6A4F'; // 솔리드 짙은 포레스트 그린
    lineColor = '2D6A4F';
    lineWidth = 0;
    shadowColor = '081F14';
    shadowOpacity = 0.12;
    shadowBlur = 8;
  } else if (styleType === 'danger') {
    fillColor = 'FFF5F5'; // 솔리드 연한 핑크
    lineColor = 'FED7D7';
    lineWidth = 1;
    shadowColor = 'E63946';
    shadowOpacity = 0.04;
    shadowBlur = 6;
  } else if (styleType === 'dark-card') {
    // 어두운 배경에 얹을 은은한 화이트 반투명 카드
    fillColor = 'FFFFFF';
    fillTrans = 92; // 8% 불투명 백색
    lineColor = 'FFFFFF';
    lineTrans = 85; // 아주 옅은 백색 테두리
    lineWidth = 1;
    shadowColor = '081F14';
    shadowOpacity = 0.2;
    shadowBlur = 8;
  }

  return slide.addShape(pptx.shapes.ROUNDED_RECTANGLE, {
    x: x, y: y, w: w, h: h,
    fill: { color: fillColor, transparency: fillTrans },
    line: { color: lineColor, width: lineWidth, transparency: lineTrans },
    rectRadius: 0.08, // 표준적이고 깔끔한 둥근 모서리
    shadow: { type: 'outer', color: shadowColor, opacity: shadowOpacity, blur: shadowBlur, offset: shadowOffset, angle: 90 }
  });
}

// 공통 헤더 추가 헬퍼 함수
function addSlideHeader(slide, title, subtitle) {
  // 백그라운드 그라데이션 적용
  applySlideBackground(slide, false);

  // 대제목 및 소제목 결합형 텍스트 박스
  slide.addText([
    { text: title + "\n", options: { fontFace: FONT_FAMILY, fontSize: 16, bold: true, color: COLOR_DARK } },
    { text: subtitle, options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_PRIMARY } }
  ], {
    x: 0.6, y: 0.22, w: 8.8, h: 0.6,
    valign: 'middle'
  });

  // 장식용 하단 포레스트 그린 라인
  slide.addShape(pptx.shapes.RECTANGLE, {
    x: 0.6, y: 0.9, w: 8.8, h: 0.02,
    fill: { color: COLOR_PRIMARY },
    line: { width: 0 }
  });
}

// -------------------------------------------------------------
// [슬라이드 1: 표지 (Dark Background)]
// -------------------------------------------------------------
const slide1 = pptx.addSlide();
applySlideBackground(slide1, true);

// 디자인 프레임 요소 (세로 라인 데코)
slide1.addShape(pptx.shapes.ROUNDED_RECTANGLE, {
  x: 0.0, y: 0.0, w: 0.3, h: 5.625,
  fill: { color: COLOR_PRIMARY },
  line: { width: 0 }
});
slide1.addShape(pptx.shapes.ROUNDED_RECTANGLE, {
  x: 0.3, y: 0.0, w: 0.07, h: 5.625,
  fill: { color: COLOR_LIGHT_GREEN },
  line: { width: 0 }
});

// 타이틀 및 서브타이틀 결합형 텍스트 박스
slide1.addText([
  { text: "카카오톡 예약 자동화 플랫폼\n", options: { fontFace: FONT_FAMILY, fontSize: 32, bold: true, color: COLOR_WHITE } },
  { text: "실시간 대화 감지 및 클라우드 연동 예약 관리 솔루션\n\n\n", options: { fontFace: FONT_FAMILY, fontSize: 12.5, color: COLOR_LIGHT_GREEN } },
  { text: "프로젝트 소개 및 기능 설명서  |  그린 에디션", options: { fontFace: FONT_FAMILY, fontSize: 10, color: COLOR_WHITE } }
], {
  x: 0.9, y: 1.35, w: 8.2, h: 3.6,
  valign: 'middle'
});


// -------------------------------------------------------------
// [슬라이드 2: 예약 연동 업종 (3 Cards)]
// -------------------------------------------------------------
const slide2 = pptx.addSlide();
addSlideHeader(slide2, '01. 카카오톡 예약을 받는 주요 업종', '매장 내 단골 고객 소모임 활성화가 매장 생존 및 단골 확보의 핵심인 비즈니스군');

const industries = [
  {
    title: '레저 및 스포츠',
    icon: '⚽',
    desc: '예약/매칭이 잦고 친목이 바탕이 되는 업종',
    items: ['• 실내 스포츠 센터: 그룹 세션 예약', '• 탁구/당구장: 동호인 매치 예약', '• 골프/볼링장: 팀 단위 라인 예약']
  },
  {
    title: '공간 대여 / 대관',
    icon: '🏢',
    desc: '정원 제한이 있고 실시간 룸 현황이 중요함',
    items: ['• 풋살장: 단체 구장 대관 예약', '• 파티룸/스튜디오: 시간별 공간 대여', '• 스터디카페: 회의실 정원 예약']
  },
  {
    title: '밀착 커뮤니티형',
    icon: '🎲',
    desc: '체류 시간이 길고 즉석 매칭이 활발한 곳',
    items: ['• 보드게임/방탈출: 이용 시간 예약', '• PC방 팀룸: 단체 좌석 지정 예약', '• 피트니스/크로스핏: 클래스 예약']
  }
];

industries.forEach((ind, index) => {
  const xPos = 0.6 + index * 3.0;
  
  // 솔리드 백색 카드 배치
  addCleanCard(slide2, xPos, 1.15, 2.7, 3.15, 'normal');

  slide2.addText([
    { text: ind.icon + " " + ind.title + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 13.5, bold: true, color: COLOR_DARK } },
    { text: ind.desc + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 9.5, color: COLOR_TEXT_MUTED } },
    { text: ind.items.join("\n\n"), options: { fontFace: FONT_FAMILY, fontSize: 10, color: COLOR_TEXT_DARK } }
  ], {
    x: xPos + 0.2, y: 1.35, w: 2.3, h: 2.8,
    valign: 'top'
  });
});


// -------------------------------------------------------------
// [슬라이드 3: 커뮤니티 활성화의 중요성 (Split layout)]
// -------------------------------------------------------------
const slide3 = pptx.addSlide();
addSlideHeader(slide3, '02. 고객 커뮤니티 구축 = 오프라인 매장의 매출 확보', '단순 예약을 넘어 고객 간 친목 네트워크가 단골 확보로 이어지는 구조');

// Left Solid Card
addCleanCard(slide3, 0.6, 1.15, 4.1, 3.15, 'normal');

slide3.addText([
  { text: "단골 고객 락인(Lock-in) 효과\n\n", options: { fontFace: FONT_FAMILY, fontSize: 14, bold: true, color: COLOR_DARK } },
  { text: "• 소모임 결속: 매장 방문 목적이 단순 소비에서 '회원 간 매치'로 전환됨\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_TEXT_DARK } },
  { text: "• 재방문율 극대화: 고객 간 친목 네트워크가 촘촘할수록 타 매장 이탈 방지\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_TEXT_DARK } },
  { text: "• 자발적 신규 유치: 단골 회원이 스스로 다른 참가자를 대관 및 예약 유도", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_TEXT_DARK } }
], {
  x: 0.9, y: 1.35, w: 3.5, h: 2.8,
  valign: 'top'
});

// Right Highlight Card (Green)
addCleanCard(slide3, 5.1, 1.15, 4.3, 3.15, 'highlight');

slide3.addText([
  { text: "단체 카톡방: 예약과 모집의 허브\n\n", options: { fontFace: FONT_FAMILY, fontSize: 14, bold: true, color: COLOR_WHITE } },
  { text: "• 일상적 소통 공간: 단골 회원과 매니저가 스케줄을 약속하는 핵심 채널\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_LIGHT_GREEN, bold: true } },
  { text: "• 대화 맥락 내 예약: 톡방 소통 중 외부 링크 이동 없이 즉각 예약 확정\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_WHITE } },
  { text: "• 동선 단절 해결: 불필요한 회원 가입 및 로그인 단계를 제거해 편의성 제공", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_WHITE } }
], {
  x: 5.4, y: 1.35, w: 3.7, h: 2.8,
  valign: 'top'
});


// -------------------------------------------------------------
// [슬라이드 4: 기존 불편함 (3 Red-tinted Cards)]
// -------------------------------------------------------------
const slide4 = pptx.addSlide();
addSlideHeader(slide4, '03. 기존 예약 방식의 고충 (Pain Points)', '채널 파편화 및 수동 관리로 인해 끊어지는 예약 동선과 관리 업무의 비효율');

const painPoints = [
  {
    title: '불편한 외부 예약 방식',
    desc: '대화방 이탈 및 동선 파편화',
    text: '• 단톡방에서 외부 사이트 이동의 불편\n\n• 매번 로그인 및 정보 입력의 번거로움\n\n• 예약 결과를 다시 단톡방에 인증하는 단절'
  },
  {
    title: '공식 챗봇의 단체방 불허',
    desc: '오픈채팅방 내 챗봇 가동 불가',
    text: '• 카카오 비즈니스 API는 1:1 대화만 지원\n\n• 단체 대화방 내 기능 작동 원천 불가\n\n• 고정 시나리오만 회신 (실시간 DB 연동 불가)'
  },
  {
    title: '점주의 수동 장부 관리',
    desc: '오버부킹 및 누락의 주 원인',
    text: '• 예약을 매니저가 엑셀/종이에 수기 기입\n\n• 피크 타임 예약 누락 및 오버부킹 빈번하게 발생\n\n• 실시간 잔여 석 정보 공유 지체'
  }
];

painPoints.forEach((pp, index) => {
  const xPos = 0.6 + index * 3.0;

  // 솔리드 연한 핑크 경고 카드 배치
  addCleanCard(slide4, xPos, 1.15, 2.7, 3.15, 'danger');

  slide4.addText([
    { text: pp.title + "\n", options: { fontFace: FONT_FAMILY, fontSize: 13.5, bold: true, color: COLOR_DARK } },
    { text: pp.desc + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 11, bold: true, color: COLOR_ACCENT_RED } },
    { text: pp.text, options: { fontFace: FONT_FAMILY, fontSize: 10, color: COLOR_TEXT_DARK } }
  ], {
    x: xPos + 0.2, y: 1.35, w: 2.3, h: 2.8,
    valign: 'top'
  });
});


// -------------------------------------------------------------
// [슬라이드 5: 해결책 및 워크플로우 (4-Step Workflow)]
// -------------------------------------------------------------
const slide5 = pptx.addSlide();
addSlideHeader(slide5, '04. 실시간 카카오톡 예약 자동 연동 4단계', '톡방 메시지 전송부터 자동 답장 발송 및 점주 단말기 푸시 알림까지 끊김 없는 4단계 자동화');

const steps = [
  {
    step: 'STEP 01',
    title: '예약 메시지 발송',
    desc: '고객이 지정된 명령 규칙에 맞춰 단톡방에 메시지를 올립니다.',
    eg: '예시: /예약 19시 홍길동',
    highlight: false,
    color: COLOR_DARK,
    subColor: COLOR_SECONDARY
  },
  {
    step: 'STEP 02',
    title: '알림 감시 및 답장',
    desc: '전용 봇 앱이 알림을 감지해 정원 확인 후 단톡방에 답장을 보냅니다.',
    eg: '예시: 홍길동님 예약 완료 (8/10명)',
    highlight: true,
    color: COLOR_WHITE,
    subColor: COLOR_LIGHT_GREEN
  },
  {
    step: 'STEP 03',
    title: '실시간 서버 동기화',
    desc: '예약 결과가 지점 클라우드 장부에 실시간으로 동기화됩니다.',
    eg: '결과: 서버 DB 내역 적재 및 갱신',
    highlight: false,
    color: COLOR_DARK,
    subColor: COLOR_SECONDARY
  },
  {
    step: 'STEP 04',
    title: '관리자 스마트폰 알림',
    desc: '동기화 완료 시 점주 및 매니저 기기로 푸시 알림이 즉시 발송됩니다.',
    eg: '결과: 관리자 푸시 및 화면 갱신',
    highlight: true,
    color: COLOR_WHITE,
    subColor: COLOR_LIGHT_GREEN
  }
];

steps.forEach((st, index) => {
  const xPos = 0.6 + index * 2.2;
  const wCard = 2.0;

  // 하이라이트 여부에 맞춰 솔리드 카드 배치
  addCleanCard(slide5, xPos, 1.55, wCard, 3.15, st.highlight ? 'highlight' : 'normal');

  slide5.addText([
    { text: st.step + "\n", options: { fontFace: FONT_FAMILY, fontSize: 10, bold: true, color: st.highlight ? COLOR_LIGHT_GREEN : COLOR_PRIMARY } },
    { text: st.title + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 12.5, bold: true, color: st.color } },
    { text: st.desc + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 9, color: st.color } },
    { text: st.eg, options: { fontFace: FONT_FAMILY, fontSize: 9.5, bold: true, color: st.subColor } }
  ], {
    x: xPos + 0.15, y: 1.7, w: wCard - 0.3, h: 2.8,
    valign: 'top'
  });

  if (index < 3) {
    slide5.addText('▶', {
      x: xPos + wCard + 0.02, y: 2.6, w: 0.15, h: 0.3,
      fontFace: FONT_FAMILY, fontSize: 13, color: COLOR_PRIMARY,
      align: 'center', valign: 'middle'
    });
  }
});


// -------------------------------------------------------------
// [슬라이드 6: 구현된 주요 기능 A: 점주용 스마트 관리 앱 (2x2 Grid)]
// -------------------------------------------------------------
const slide6 = pptx.addSlide();
addSlideHeader(slide6, '05. 구현 기능: 점주 및 관리자용 모바일 관리 앱', '매장 점주와 직원이 예약을 실시간 모니터링하고 직접 제어할 수 있는 스마트 관리 화면');

const adminFeatures = [
  {
    title: '실시간 예약 대시보드 현황판',
    icon: '📊',
    desc: '• 현황 모니터링: 시간별 정원 및 예약 명단 실시간 조회\n• 진행률 시각화: 정원 대비 예약 인원 비율 카드형 노출'
  },
  {
    title: '간편 예약 관리 제어 및 수동 조작',
    icon: '✏️',
    desc: '• 간편 예약 제어: 3초 내 예약자 추가/수정/대기/취소\n• 양방향 동기화: 점주 수정 내역이 봇과 서버에 즉시 전파'
  },
  {
    title: '즉각적인 예약 푸시 알림',
    icon: '🔔',
    desc: '• 실시간 알림: 단톡방 예약 성사 시 스마트폰 FCM 푸시\n• 자동 화면 연결: 푸시 클릭 시 예약 상세 뷰어로 진입'
  },
  {
    title: '다중 지점 생성 및 매장 직원 관리',
    icon: '👥',
    desc: '• 다중 매장 제어: 점주 계정 하나로 여러 지점 선택 관리\n• 직원 권한 부여: 7일 만기 초대 코드로 직원 초대 및 등록'
  }
];

adminFeatures.forEach((feat, index) => {
  const col = index % 2;
  const row = Math.floor(index / 2);

  const xPos = 0.6 + col * 4.5;
  const yPos = 1.15 + row * 1.7;

  // 솔리드 백색 카드 배치
  addCleanCard(slide6, xPos, yPos, 4.3, 1.5, 'normal');

  slide6.addText([
    { text: feat.icon + " " + feat.title + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 14, bold: true, color: COLOR_DARK } },
    { text: feat.desc, options: { fontFace: FONT_FAMILY, fontSize: 9.5, color: COLOR_TEXT_DARK } }
  ], {
    x: xPos + 0.2, y: yPos + 0.15, w: 3.9, h: 1.3,
    valign: 'top'
  });
});


// -------------------------------------------------------------
// [슬라이드 7: 구현된 주요 기능 B: 자동 응답 예약 챗봇 및 설정 (2x2 Grid)]
// -------------------------------------------------------------
const slide7 = pptx.addSlide();
addSlideHeader(slide7, '06. 구현 기능: 24시간 자동 응답 예약 챗봇 및 설정', '매장에 거치된 안드로이드 기기를 활용해 단톡방 예약을 파싱하고 템플릿 설정을 커스텀하는 기능');

const botFeatures = [
  {
    title: '단톡방 명령어 자동 파싱 및 답장',
    icon: '💬',
    desc: '• 키워드 자동 감지: 단톡방 내 /예약, /취소, /조회 식별\n• 실시간 자동 답장: 잔여 정원 확인 후 단톡방 즉시 회신'
  },
  {
    title: '채팅방 성격 분류 및 권한 관리',
    icon: '🔒',
    desc: '• 대화방 유형 분류: 예약방, 일반 대화방, 관리자방 지정\n• 보안 권한 제어: 관리자 전용 명령어 도용 방지 정책 적용'
  },
  {
    title: '예약 항목 및 자동 응답 템플릿 설정',
    icon: '⚙️',
    desc: '• 예약 항목 관리: 예약 명칭 및 정원 한계를 앱에서 제어\n• 연쇄 데이터 삭제: 항목 삭제 시 해당 예약 내역 자동 소거'
  },
  {
    title: '영업 주기 기준 예약 자동 초기화 시각 설정',
    icon: '🕒',
    desc: '• 일괄 자동 초기화: 영업 주기에 맞춘 장부 자동 초기화\n• 설정 백업 복원: 봇 명령어 및 템플릿 서버 상시 백업'
  }
];

botFeatures.forEach((feat, index) => {
  const col = index % 2;
  const row = Math.floor(index / 2);

  const xPos = 0.6 + col * 4.5;
  const yPos = 1.15 + row * 1.7;

  // 솔리드 백색 카드 배치
  addCleanCard(slide7, xPos, yPos, 4.3, 1.5, 'normal');

  slide7.addText([
    { text: feat.icon + " " + feat.title + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 14, bold: true, color: COLOR_DARK } },
    { text: feat.desc, options: { fontFace: FONT_FAMILY, fontSize: 9.5, color: COLOR_TEXT_DARK } }
  ], {
    x: xPos + 0.2, y: yPos + 0.15, w: 3.9, h: 1.3,
    valign: 'top'
  });
});


// -------------------------------------------------------------
// [슬라이드 8: 백그라운드 구동 아키텍처 및 복구력 (Technical Column)]
// -------------------------------------------------------------
const slide8 = pptx.addSlide();
addSlideHeader(slide8, '07. 시스템 동작 안정성 및 데이터 유실 방지 장치', '24시간 무중단 알림 수집 감시 엔진과 네트워크 단절 복구 아키텍처');

// Left: Watchdog (솔리드 그린 하이라이트 카드)
addCleanCard(slide8, 0.6, 1.15, 4.1, 3.15, 'highlight');

slide8.addText([
  { text: "🛡️ 포그라운드 Keep-Alive 및 5분 주기 Watchdog\n", options: { fontFace: FONT_FAMILY, fontSize: 13.5, bold: true, color: COLOR_WHITE } },
  { text: "(Android Foreground Service & Rebind Scheduler)\n\n", options: { fontFace: FONT_FAMILY, fontSize: 8.5, bold: true, color: COLOR_LIGHT_GREEN } },
  { text: "• 상시 실행 서비스 등록: Foreground 알림 노출로 OS 프로세스 강제 종료 방어\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_WHITE } },
  { text: "• 5분 주기 Watchdog: 독립 스레드가 챗봇 서비스 작동 여부 상시 감시\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_WHITE } },
  { text: "• 자동 자가 치유: 연결 단절 감지 시 requestRebind 즉시 자동 호출", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_WHITE } }
], {
  x: 0.9, y: 1.35, w: 3.5, h: 2.8,
  valign: 'top'
});

// Right: SQLite Queue (솔리드 백색 카드)
addCleanCard(slide8, 5.1, 1.15, 4.3, 3.15, 'normal');

slide8.addText([
  { text: "⏳ 오프라인 대기 큐 및 자동 재시도 알고리즘\n", options: { fontFace: FONT_FAMILY, fontSize: 13.5, bold: true, color: COLOR_DARK } },
  { text: "(SQLite Sync Queue & Exponential Backoff)\n\n", options: { fontFace: FONT_FAMILY, fontSize: 8.5, bold: true, color: COLOR_PRIMARY } },
  { text: "• 오프라인 예약 보존: 인터넷 단절 시 내역을 로컬 SQLite에 임시 보존\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_TEXT_DARK } },
  { text: "• 지수 백오프 전송: 네트워크 연결 정상 복구 시 순차 서버 업로드\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_TEXT_DARK } },
  { text: "• 멱등성 검증 탑재: UUID 식별자 할당으로 중복 전송 및 데이터 충돌 방지", options: { fontFace: FONT_FAMILY, fontSize: 10.5, color: COLOR_TEXT_DARK } }
], {
  x: 5.4, y: 1.35, w: 3.7, h: 2.8,
  valign: 'top'
});


// -------------------------------------------------------------
// [슬라이드 9: 실제 도입 및 운영 사례 (Case Studies)]
// -------------------------------------------------------------
const slide9 = pptx.addSlide();
addSlideHeader(slide9, '08. 실제 도입 및 운영 사례 (Case Studies)', '오프라인 매장 현장에서 예약 리소스를 극대화하고 오버부킹을 없앤 실제 제휴 사례');

const cases = [
  {
    shop: 'A 실내 스포츠 라운지 강남점',
    status: '도입 완료 및 가동 중',
    setup: '매장 내 태블릿 1대 배치 (예약봇)',
    result: '• 일평균 약 90건 자동 예약 처리\n• 수동 입력 오버부킹율 0% 달성\n• 예약 대조 리소스 대폭 감축'
  },
  {
    shop: 'B 실내 탁구클럽 동호회',
    status: '도입 완료 및 가동 중',
    setup: '동호인 오픈 단톡방 연동 챗봇',
    result: '• 회원 친목 게임 매칭 참여율 35% 상승\n• 실시간 대관 정원 도달 시간 단축\n• 코치진 스케줄 관리 단순화'
  },
  {
    shop: 'C 스크린골프 / 볼링장',
    status: '도입 및 커스텀 조율 중',
    setup: '라인별 예약 전용 알림 챗봇',
    result: '• 카톡 예약 상담 전화 리소스 85% 감축\n• 실시간 룸 현황판 공유 자동화\n• 대기열 알림 연동으로 중복 방지'
  }
];

cases.forEach((cs, index) => {
  const xPos = 0.6 + index * 3.0;
  
  // 솔리드 백색 카드 배치
  addCleanCard(slide9, xPos, 1.15, 2.7, 3.15, 'normal');

  slide9.addText([
    { text: cs.shop + "\n", options: { fontFace: FONT_FAMILY, fontSize: 13.5, bold: true, color: COLOR_DARK } },
    { text: cs.status + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 9.5, bold: true, color: COLOR_PRIMARY } },
    { text: "• 도입 형태:\n  " + cs.setup + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 10, bold: true, color: COLOR_TEXT_DARK } },
    { text: "• 도입 결과 및 성과:\n" + cs.result, options: { fontFace: FONT_FAMILY, fontSize: 10, color: COLOR_TEXT_DARK } }
  ], {
    x: xPos + 0.2, y: 1.35, w: 2.3, h: 2.8,
    valign: 'top'
  });
});

slide9.addText('※ [작성용 가이드]: 실제 제휴 매장 및 도입처의 상세 데이터로 텍스트를 즉시 변경하여 활용할 수 있습니다.', {
  x: 0.6, y: 4.5, w: 8.8, h: 0.3,
  fontFace: FONT_FAMILY, fontSize: 9, color: COLOR_TEXT_MUTED
});


// -------------------------------------------------------------
// [슬라이드 10: 결론 및 로드맵 (Dark Background)]
// -------------------------------------------------------------
const slide10 = pptx.addSlide();
applySlideBackground(slide10, true);

// 디자인 프레임 (상단 가로 데코바)
slide10.addShape(pptx.shapes.RECTANGLE, {
  x: 0.0, y: 0.0, w: 10.0, h: 0.11,
  fill: { color: COLOR_PRIMARY },
  line: { width: 0 }
});

// 타이틀과 서브타이틀
slide10.addText([
  { text: "예약 자동화와 커뮤니티 결속을 동시에\n", options: { fontFace: FONT_FAMILY, fontSize: 24, bold: true, color: COLOR_WHITE } },
  { text: "단톡방 대화에서 예약 장부까지 연결하는 단 하나의 오프라인 운영 솔루션", options: { fontFace: FONT_FAMILY, fontSize: 11, color: COLOR_LIGHT_GREEN } }
], {
  x: 0.8, y: 0.6, w: 8.4, h: 0.9,
  valign: 'middle'
});

// 로드맵 타이틀
slide10.addText('■ 서비스 고도화 및 기술 로드맵', {
  x: 0.8, y: 1.75, w: 8.4, h: 0.3,
  fontFace: FONT_FAMILY, fontSize: 12, bold: true, color: COLOR_LIGHT_GREEN
});

const roadmapSteps = [
  { step: 'Phase 1', title: '예약 대기열 자동화', detail: '정원 초과 시 대기 순서 지정. 예약 취소 시 대기 순번 고객 예약 자동 승계 및 톡방 알림 발송' },
  { step: 'Phase 2', title: '운영사 통합 웹 콘솔', detail: '신규 가맹 매장 개설, 라이선스 승인/만기 관리, 지점 봇 상태를 감시하는 본사 웹 어드민 개발' },
  { step: 'Phase 3', title: '클라이언트 보안 강화', detail: '비인가 임의 단말의 API 탈취 방어. Play Integrity 및 Firebase App Check 보안 체계 구축' },
  { step: 'Phase 4', title: 'AI 예측 통계 리포트', detail: '누적된 예약 분석을 바탕으로 요일별 혼잡 시간 예측 모델 탑재 및 단골 재방문 주기 리포팅' }
];

roadmapSteps.forEach((rms, index) => {
  const xPos = 0.6 + index * 2.2;

  // 어두운 배경에 얹을 은은한 화이트 반투명 카드 배치
  addCleanCard(slide10, xPos, 2.2, 2.0, 2.2, 'dark-card');

  slide10.addText([
    { text: rms.step + "\n", options: { fontFace: FONT_FAMILY, fontSize: 10.5, bold: true, color: COLOR_LIGHT_GREEN } },
    { text: rms.title + "\n\n", options: { fontFace: FONT_FAMILY, fontSize: 11.5, bold: true, color: COLOR_WHITE } },
    { text: rms.detail, options: { fontFace: FONT_FAMILY, fontSize: 8.5, color: COLOR_LIGHT_GREEN } }
  ], {
    x: xPos + 0.15, y: 2.35, w: 1.7, h: 1.9,
    valign: 'top'
  });
});


// -------------------------------------------------------------
// [슬라이드 11: 감사합니다 (Dark Background)]
// -------------------------------------------------------------
const slide11 = pptx.addSlide();
applySlideBackground(slide11, true);

// 세로 데코바
slide11.addShape(pptx.shapes.ROUNDED_RECTANGLE, {
  x: 0.0, y: 0.0, w: 0.3, h: 5.625,
  fill: { color: COLOR_PRIMARY },
  line: { width: 0 }
});
slide11.addShape(pptx.shapes.ROUNDED_RECTANGLE, {
  x: 0.3, y: 0.0, w: 0.07, h: 5.625,
  fill: { color: COLOR_LIGHT_GREEN },
  line: { width: 0 }
});

slide11.addText([
  { text: "감사합니다\n\n", options: { fontFace: FONT_FAMILY, fontSize: 44, bold: true, color: COLOR_WHITE } },
  { text: "Q&A 및 문의사항\n\n\n", options: { fontFace: FONT_FAMILY, fontSize: 16, bold: true, color: COLOR_LIGHT_GREEN } },
  { text: "• 이메일: contact@example.com\n\n• 연락처: 010-XXXX-XXXX\n\n• 주소: [회사/사무실 주소 작성용]", options: { fontFace: FONT_FAMILY, fontSize: 10, color: COLOR_WHITE } }
], {
  x: 1.1, y: 1.35, w: 7.5, h: 3.4,
  valign: 'middle'
});


// 파일 쓰기 수행
console.log('10 x 5.625 인치 그린 테마 PPTX 생성 작업 시작...');
pptx.writeFile({ fileName: 'presentation.pptx' })
  .then(fileName => {
    console.log(`성공적으로 파워포인트 발표 파일이 생성되었습니다: ${fileName}`);
  })
  .catch(err => {
    console.error('파워포인트 파일 생성 실패:', err);
  });
