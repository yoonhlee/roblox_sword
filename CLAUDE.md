# 강화의 대장간 (ForgeFever) — Claude 작업 메모

Claude Code 가 이 저장소에서 일할 때 가장 먼저 읽는 파일이다.
새 세션은 대화 기록이 없으므로 **여기 적힌 것이 기억의 전부**라고 생각한다.

**기획의 단일 기준은 `docs/통합-기획서.md` 다.** 다른 문서와 내용이 다르면 통합 기획서를 따른다.
새 결정이 생기면 `docs/기획서.md`(근거·제안 기록)에 기록하고 **통합 기획서도 같은 내용으로
갱신**한다. 동료용 요약인 브리프도 함께 맞춘다.

관련 문서

| 문서 | 내용 |
| --- | --- |
| `docs/통합-기획서.md` | **기준 문서.** 확정 기획을 공식으로 정리, 미정 항목, 지금 코드와의 차이. 다른 AI 와 협업할 때도 이것만 주면 된다 |
| `docs/기획서.md` | 결정의 근거와 제안·승인 기록(P1~), 결정 대기(D) 상세. 지난 안(폐기된 수치)도 기록으로 남아 있으니 수치는 통합 기획서 기준으로 본다 |
| `docs/기획-현황-브리프.md` | 동료용 요약: 바뀐 기획, 판단 근거, 결정 대기 우선순위 |
| `docs/원본-지시서.md` | 처음 받은 지시서 원문. **옛 기획**(배틀, 파괴, 골드 팩 등)이라 기획 기준으로 쓰지 않는다 |
| `docs/economy.md` | 프로토타입 확률표 기준 옛 경제 분석. 새 기획에는 맞지 않는다 |
| `docs/시작하기.md` | 개발자가 Studio 에서 프로토타입을 실행하는 법 |
| `README.md` | 개발 환경, 폴더 구조, 운영 명령어, 출시 체크리스트 (프로토타입 기준) |

---

## 1. 개발자와 일하는 방식

- 개발자는 **개발 지식이 없다.** 기술적인 판단(구조, 라이브러리, API 사용법)은
  묻지 말고 로블록스 표준 방식으로 내가 정해서 진행한다. (2026-09 지시:
  "모든 것을 나한테 묻지 말고 그냥 네가 쭉 완성시켜")
- 설명은 쉬운 한국어, 반말 톤. 기술 용어는 꼭 필요할 때만, 풀어서.
- 결과를 보고할 때는 **검증한 것과 못 한 것을 구분해서** 솔직하게 말한다.
  특히 나는 Roblox Studio 를 실행할 수 없으므로 UI·DataStore 실동작은 "미확인"이다.

### Git 원칙 (2026-11-14 개발자 지시, 최우선)

1. **개발자가 명시적으로 "커밋해줘"라고 말할 때만 커밋한다.** "작성해줘", "고쳐줘",
   "완성해줘" 등 다른 어떤 말도 커밋 허락이 아니다. 커밋하지 않은 것은 푸시도 하지 않는다.
   아래 다른 절에 "함께 커밋" 같은 말이 있어도 이 원칙이 우선한다.
2. **`main` 브랜치에는 절대 커밋·머지하지 않는다.** `main` 수정은 개발자가 직접 한다.
   나는 `main` 을 받아오기(fetch/pull)만 할 수 있다. PR 머지도 하지 않는다.

### 지금 단계: 기획 (2026-11 ~)

개발자가 게임 기획 아이디어를 제안하면:

1. **장점과 단점**을 말한다. (가능하면 기존 시스템에 미치는 영향, 작업량,
   로블록스 정책·수익화·어뷰징 측면까지)
2. 내 의견(추천/비추천/조건부)을 한 줄로 덧붙인다.
3. 개발자가 **승인하면** `docs/기획서.md` 에 반영하고 제안 기록 표를 갱신한다.
   `docs/통합-기획서.md` 와 브리프도 같은 내용으로 맞춘다.
4. **승인 전에는 기획서도 코드도 바꾸지 않는다.** 보류·거절도 기록 표에 남긴다.
5. 기획서에 들어간 것을 구현하는 건 개발자가 구현을 요청했을 때 한다.

### 바꾸면 안 되는 것 (승인 없이)

- 밸런스 수치 (`src/shared/Config/*` 의 확률·비용·보상). 제안만 하고 승인 후 적용.
- 공개 확률표. 플레이어 신뢰 문제라 특히 신중히.
- **골드는 Robux 로 직접도 간접적으로도 얻을 수 없다** (기획서 P6). 골드 팩 금지,
  골드 획득량을 늘리는 유료 혜택도 금지. 로블록스 정책상 "Robux 로 살 수 있는 화폐로 하는
  강화"는 유료 확률형 아이템이기 때문이다.
- 유료 확률형 상품은 **방지권 확률형 1종만** 승인됐다 (P8). 다른 확률형 상품은 먼저 확인.
  구현할 때는 통합 기획서 7절의 정책 요구사항(사기 전 % 공개·합계 100%, 방지권 켜면 표시
  확률 변경, `ArePaidRandomItemsRestricted` 유저에겐 확률형 숨김, 결제 재시도 시 재추첨
  금지)을 지킨다.
- 상한 구매·새 검 뽑기, 경주 보상, 트레드밀, 도감 업그레이드에 Robux 가 닿는 상품은 만들지 않는다.
- 방지권 외 추가 수익화(D24)는 협의 중이다. 승인 전에는 구현하지 않는다.
- 게임 안의 모든 확률은 화면에 공개한다 (P10).

---

## 2. 확정된 정체성

| 항목 | 값 |
| --- | --- |
| 게임 이름 | 강화의 대장간 / Forge Fever |
| 내부 식별자 | `ForgeFever` (Rojo 프로젝트명, DataStore 접두사) |
| 결과 피드 NPC | 모루 영감 (영문 Old Anvil) — 무뚝뚝하고 짧은 말투 |
| 무기 | 기본 20종 (등급 common·rare·epic·legend). 지금 있는 5종: 무쇠 검, 잉걸불 검, 물결 송곳니, 폭풍 바늘, 새벽가르기. 나머지 15종은 미정(D22). 전부 오리지널 |
| 타깃 | 모바일 우선, 한국어 기본 + 영어 |
| 영감 | 채팅 봇형 강화 게임의 "버튼 한 번 → 결과 텍스트" 감성. **이름·캐릭터·대사·이미지·문구는 전부 오리지널**, 기존 서비스 것을 베끼지 않는다 |

---

## 3. 코드 규칙 (원본 지시서에서 계속 유효한 것)

- 모든 Luau 파일 맨 위에 `--!strict`.
- **서버 권위**: 확률·골드·레벨·경주 거리·능력 판정은 서버에서만. 클라이언트는 요청과 표시만.
  클라이언트가 보낸 레벨/골드/결과/거리 값은 절대 신뢰하지 않는다.
- 밸런스 수치는 코드에 박지 말고 `src/shared/Config/` 에 데이터로.
- 서버 함수는 입력 타입 검증부터. 실패는 에러 대신 `{ ok = false, reason = "..." }`.
  새 `reason` 을 만들면 `Locale` 의 `error.<reason>` 과 `tests/Locale.spec.luau` 의
  `REASONS` 목록에도 추가한다.
- 화면 문자열은 `src/shared/Locale.luau` 의 키로만. 한국어·영어 키는 항상 짝을 맞춘다.
- **로블록스 API 를 지어내지 않는다.** 확신이 없으면 공식 문서를 확인한다(7절 참고).
  실제 사례: Phase 0 에서 지어낸 `"$optional": true` 때문에 Rojo 프로젝트가 아예
  파싱되지 않았다. 올바른 문법은 `"$path": { "optional": "Packages" }`.
- 데이터 변경 패턴: `DataService.getActiveData(player)` 로 받고 → **yield 없이** 전부
  바꾸고 → 마지막에 `DataService.replicate(player)` 한 번. yield 가 필요하면
  (필터링, 웹 요청) yield 가 끝난 뒤 데이터를 **다시** 가져온다.
- 재화 증감은 반드시 `EconomyService` 를 거친다 (기록·음수 방지).
- 스키마를 바꾸면 `Types.SCHEMA_VERSION` 을 올리고 `DataService.migrate` 에 단계 추가.
  기존 데이터를 절대 버리지 않는다.
- 커밋은 (허락받은 경우에만) 기능 단위, 메시지는 한국어. 개발 브랜치는 세션마다 지정되거나
  개발자가 정한 `claude/...` 브랜치다. `main` 은 받아오기만 한다.

---

## 4. 현재 상태 (2026-11-14 기준)

**개발 3단계까지 코드 작성 완료, 커밋 전.** Luau 46개 파일, 테스트 83개 통과.
Studio 실동작은 한 번도 확인하지 못했다. 개발자가 Studio 에서 돌려 보고 Output 오류를 알려 주기로 했다.

### 개발 계획 (개발자 지시)

| 단계 | 내용 | 상태 |
| --- | --- | --- |
| 1 | 걷어 내기 (통합 기획서 10-1절) | 코드 완료 · Studio 확인 대기 |
| 2 | 강화 새 규칙 (통합 기획서 3절) | 코드 완료 · Studio 확인 대기 |
| 3 | 검 보관함·착용·소지 상한 구매·뽑기·도감, 스키마 v4 | 코드 완료 · Studio 확인 대기 |
| 4 | 추격 생존 경주 + 로비 트레드밀 1단계 (거리는 서버 계산, D16·D6 은 자리만) | 시작 전 |
| 5 | 방지권 상품 3종 + 천장 포인트 + **파편 뽑기** (수치·ID 는 비워 두고, 비면 숨김) | 시작 전 |

일하는 방식 (개발자 지시, 2026-11-14):

- **가짜 로블록스 환경 같은 큰 검증 도구는 만들지 않는다.** 자체 검증은 6절의 필수 항목(테스트, 문법, 포맷, 린트,
  Rojo 빌드)까지만 하고, 실제 실행과 디버깅은 개발자가 Studio 에서 한다. 토큰을 아끼는 쪽으로 일한다.
- 단계 보고에 넣을 것: ① 만든 것·지운 것 ② 검증한 것 / 못 한 것 + Studio 확인 절차 ③ 임시값을 넣은 미정 항목
  ④ 기획서에 없는 판단 ⑤ 커밋 준비 여부.
- 미정 수치(D 항목)는 지어내지 않는다. 필요하면 Config 에 "미정(Dxx)" 표시를 단 임시값. 추천치는 그대로 쓴다.
- 4단계 매칭: 대기열 **20명**이 차면 즉시 출발, 아니면 10초에 대기자 전원 출발(P43, 숫자는 나중에 조절).

### 서버 (`src/server/services/`, 부트스트랩 순서대로)

| 서비스 | 하는 일 |
| --- | --- |
| DataService | ProfileStore 세션, 템플릿, 마이그레이션 호출(`Pure/DataMigration`, v1→v4), 차단 확인, 복제, 설정 변경 |
| AnalyticsService | 재화 source/sink·강화·퍼널 로그, 골드 급증 탐지 (Roblox Analytics 연결은 미완) |
| LiveOpsService | DataStore 원격 설정 60초 폴링: 점검·공지·확률 버프 이벤트 |
| EconomyService | 재화 증감 단일 창구(배수 없음), 출석·플레이 보상, 접속 중 날짜 변경 확인 |
| CodexService | 검별 최고 레벨과 5·10·15·20강 달성 기록 (`codex["검id:구간"]`). 보상 효과는 D16 미정이라 기록만 |
| EnhanceService | 착용 검 강화(2구간, 실패 시 10강), 이름 짓기(필터링), 레이트 리밋+락, 15강 공지, GetState |
| SwordService | 착용 검 바꾸기, 소지 상한 구매 + 새 검 뽑기 |
| ChatCommandService | `/강화 [보호]` `/확률` `/정보` `/도움말` |
| ShopService | 방지권 묶음 상품 틀, ProcessReceipt(저장 확인 후 지급 완료). 상품 3종은 5단계 |
| LeaderboardService | 최고 강화 레벨 순위 (OrderedDataStore, 예산 확인) |
| AdminService | `/관리` 명령, 감사 로그. `ADMIN_USER_IDS` 가 비면 비활성 |
| RateLimiter | 유틸 (생명주기 없음) |

`src/server/vendor/ProfileStore.luau` — 외부 원본(커밋 45c9847, Apache 2.0). 고치지 않는다(`.styluaignore` 로 포맷에서도 제외).

### 클라이언트 (`src/client/controllers/`)

Sound → Effects → Feed → OddsTable → Shop → Sword → Collection → UI 순서로 초기화.
`ClientState` 가 서버가 보낸 데이터의 로컬 사본(표시 전용)과 "방지권 사용" 스위치를 들고 있다.
확률표·뽑기 확률표·도감은 복제받은 데이터와 `Pure/` 함수로 클라이언트가 그린다(서버와 같은 함수라 어긋나지 않는다).

### 공유 (`src/shared/`)

- `Config/` — EnhanceTable(확률표, 비용 상수), EconomyConfig, Weapons(5종, 뽑기 가중치, 상한 가격 상수), Products, Game
- `Pure/` — EnhanceLogic, SwordLogic, DataMigration, Format (Roblox API 없음, 테스트 대상)
- `Types` (스키마 v4), `Remotes`, `Locale` (ko/en 각 113키)

### 저장 스키마 v4

`swords[검id] = { id, level, bestLevel, customName? }`, `equippedId`, `swordCapacity`, `pityPoints`.
v3 의 `weapon` 은 첫 검으로 옮기고 필드는 지우지 않았다. 배틀·업적 필드도 그대로 두고 읽지도 쓰지도 않는다.
`stats.destroyed` 는 이름만 옛것이고 지금은 "2구간 실패 횟수"다.

### 임시값(미정)과 비어 있는 곳

| 항목 | 지금 값 | 결정 |
| --- | --- | --- |
| 2구간 실패 시 파편 | `floor(레벨^1.5)` (프로토타입 공식) | D12 |
| 방지권 상품 | 5개 묶음 1종, ID 0 이라 안 보임 | D12, 5단계 |
| 검 4종 등급 | rare·rare·epic·legend (프로토타입 값) | D22 |
| 도감 기념 업그레이드 | 달성 기록만 | D16 |
| 시작 골드 100, 출석, 15분 보상 | 프로토타입 값 | 재검토 대상 |

- **시작 골드 문제**: 새 비용에서 0→1강이 200골드라, 새 유저(100 + 첫 출석 100)는 한 번만 강화할 수 있다.
  "첫 접속 강화 3회 안내"를 유지하려면 최대 1,000골드가 필요하다. 개발자 결정 대기.
- **4단계 전까지 골드 수입이 거의 없다**(출석·15분 보상뿐). Studio 테스트는 `/관리 골드` 로 한다(`ADMIN_USER_IDS` 필요).
- 방지권을 얻는 길도 5단계 전까지는 `/관리 방지권` 뿐이다.
- 사운드 에셋, 검 외형(3D 모델), 로비·경주 코스 공간이 비어 있다.

### 알아 둘 것

- 접속한 채 자정(UTC)을 넘기면 그날 출석 골드를 못 받는다(예전부터의 동작, 그대로 뒀다. 출석 재검토 때 함께 정한다).
- `ANOMALY_GOLD_DELTA`(60초에 20만)는 경주 보상(최대 약 10억)이 생기면 계속 울린다. 4단계에서 조정한다.
- 내려받은 `luau-lsp` 실행 파일은 이 환경의 권한 설정이 실행을 거부했다. 다시 시도하지 말 것.

---

## 5. 내린 결정과 이유 (다시 뒤집기 전에 이유부터 볼 것)

| 결정 | 이유 |
| --- | --- |
| ProfileStore 를 vendor 로 포함 | 비개발자가 Wally 없이 실행할 수 있게. DataService 는 vendor 와 ServerPackages 둘 다 찾는다 |
| `ForgeFever.rbxlx` 를 커밋 | Studio 더블클릭만으로 실행. **코드를 바꾸면 `rojo build -o ForgeFever.rbxlx` 로 다시 만들어 함께 커밋** |
| LocalizationTable 대신 `Locale.luau` | 외부 의존 없이 바로 동작. 키 이름은 그대로 두고 나중에 옮길 수 있다 |
| ProcessReceipt 는 PurchaseId 캐싱 방식 | ProfileStore 공식 문서 권장. 저장이 확인된 뒤에만 PurchaseGranted |
| `purchaseHistory` 를 배열로 (v2) | 오래된 것부터 버려 200개 유지 |
| 지어 준 무기 이름은 레벨이 바뀌어도 유지 | 사용성. (판매는 P41 로 삭제, "파괴"는 새 기획에서 "실패 → 10강 복귀"로 바뀜) |
| (폐지) 배틀 승패·Elo 레이팅 | 1:1 배틀이 폐지돼(P4) 더 이상 쓰지 않는다. 코드는 걷어 낼 대상 |
| 채팅 명령어를 서버 런타임에 생성 | 코드로 관리하려고. **Studio 실동작 미확인** |
| `default.project.json` 에 `TextChatService.ChatVersion = TextChatService` | 이 속성의 기본값은 옛 채팅이고 스크립트로는 못 바꾼다. 안 넣으면 빌드한 플레이스에서 채팅 명령이 등록되지 않을 수 있다 |
| 검 목록은 `swords[검id]` 딕셔너리 | 같은 검을 두 개 가질 수 없어서 id 가 곧 키다. 가진 검 수 = 키 개수 |
| 템플릿의 `swords` 는 빈 표, 기본 검은 `DataMigration.repair` 가 지급 | 템플릿에 넣으면 Reconcile 이 옛 데이터에도 끼워 넣어 마이그레이션과 엉킨다 |
| 세션 종료 신호는 "밖에서 끝난 경우"만 처리 | `EndSession()` 이 신호를 그 자리에서 부른다. 구분하지 않으면 나갈 때 리스너가 두 번 불리고 차단 안내가 엉뚱하게 나간다 |
| 금액 반올림: 강화 비용·상한 가격은 반올림 | 기획서에 규칙이 없어 정했다. 검이 1개면 공식 값과 정확히 같다 |
| 뽑기 확률 표시는 소수 둘째 자리, 합이 정확히 100 이 되게 남는 몫을 나눠 줌 | 그냥 반올림하면 합이 99.99 가 될 수 있다. 실제 추첨은 원래 가중치로 한다 |

---

## 6. 이 클라우드 환경에서 검증하는 법

컨테이너는 세션마다 새로 만들어질 수 있다. 설치한 툴은 사라진다고 가정한다.

```bash
# 순수 로직 테스트·시뮬레이션용 Luau 실행기 (Lune 대체, 약 40초 빌드)
cargo build --release --manifest-path tools/luaurun/Cargo.toml
R=tools/luaurun/target/release/luaurun
$R tests/run.luau                         # 테스트 83개
$R tools/simulate_economy.luau            # 강화 시뮬레이션 (0강→20강 기대 시도 약 9,440회가 나와야 한다)
$R --check $(git ls-files '*.luau')       # 전 파일 문법 검사

# 로블록스 툴체인 (crates.io 에서 빌드, 수 분)
cargo install rojo selene --locked
cargo install stylua --locked --features luau   # luau 기능 없이 깔면 .luau 를 하나도 검사하지 않고 통과한다
rojo build -o ForgeFever.rbxlx            # 프로젝트가 실제로 빌드되는지
stylua --check src tests tools
```

- **selene**: `selene generate-roblox-std` 는 프록시 TLS 때문에 실패한다. 임시 설정
  (`std = "luau"`, `exclude = ["src/server/vendor/**"]`, `undefined_variable = "allow"`)을
  스크래치 폴더에 만들어 `selene --config <그 파일> src tests tools` 로 돌린다.
- **Lune** 은 이 환경에 없다. 개발자 PC 에서는 `lune run tests/run`.
- **로블록스 정책 문서**: 유료 확률형 아이템 정책 원문은
  `.../content/en-us/production/monetization/paid-random-items.md`.
  `devforum.roblox.com` 은 이 환경에서 접속이 안 된다.
- **로블록스 공식 문서**: `create.roblox.com` 은 차단된다.
  `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/...` 로
  같은 내용을 읽을 수 있다 (예: `reference/engine/classes/TextService.yaml`).
- ProfileStore 문서는 `git clone https://github.com/MadStudioRoblox/ProfileStore` 의 `docs/`.

코드를 바꾼 뒤 커밋 전 체크: 테스트 → `--check` → `stylua --check` → selene →
`rojo build` → `ForgeFever.rbxlx` 갱신.

---

## 7. 미해결 · 대기 중

- **기획 결정 대기**: `docs/통합-기획서.md` 9절 (상세 근거는 `docs/기획서.md` 5절).
- **Studio 실동작 확인 대기**: UI 렌더링, DataStore 저장, 채팅 명령어 등록.
  개발자가 Output 창 오류를 보내 주면 그걸 기준으로 고친다.
- `rokit.toml` 버전 문자열 미검증 (cargo 로 확인한 실제 최신: rojo 7.7.0, selene 0.31.0, stylua 2.5.2).
- Roblox `AnalyticsService` 실제 연결 안 됨 (`AnalyticsService.sendToRoblox` 자리만 있음).
- 개발자 입력 필요: `ADMIN_USER_IDS`, 방지권 상품 ID, 사운드 에셋 ID.
