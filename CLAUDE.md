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

원본 지시서의 Phase 0~7 **전부 구현 완료**. Luau 46개 파일, 테스트 73개 통과.

> ⚠️ **기획 전환 (2026-11-14 승인, 코드 미반영)**: 1:1 배틀 폐지, 게임 목표를
> **추격 생존 경주**로, 강화를 **2구간**(1~10강 실패 없음 / 11~20강 실패 시 10강 복귀)으로
> 바꾼다. 검 여러 개(뽑기·착용·도감 업그레이드), 트레드밀이 추가되고, 골드 팩·게임패스·업적·
> 판매·방지권 골드 구매는 삭제됐다.
> 아래 표는 *지금 코드* 기준이다. 새로 만들 때는 **`docs/통합-기획서.md`** 를 기준으로 하고
> (걷어 낼 것·바꿀 것은 10절), 배틀 코드 위에 기능을 쌓지 않는다.
> 결정 대기는 통합 기획서 9절, 승인 기록(P1~P42)은 `docs/기획서.md` 6절.

### 서버 (`src/server/services/`, 부트스트랩 순서대로)

| 서비스 | 하는 일 |
| --- | --- |
| DataService | ProfileStore 세션, 템플릿, 마이그레이션(v1→v2→v3), 차단 확인, 복제, 설정 변경 |
| AnalyticsService | 재화 source/sink·강화·퍼널 로그, 골드 급증 탐지 (Roblox Analytics 연결은 미완) |
| LiveOpsService | DataStore 원격 설정 60초 폴링: 점검·공지·확률 버프 이벤트 |
| EconomyService | 재화 증감 단일 창구, 일일 초기화, 출석·플레이 보상, 방지권 구매 |
| EnhanceService | 강화·판매·이름 짓기(필터링), 레이트 리밋+락, 15강 공지 |
| ChatCommandService | `/강화 [보호]` `/판매` `/배틀 [닉]` `/확률` `/정보` `/도움말` |
| BattleService | 도전/수락(15초), 승패·보상·Elo, 어뷰징 방지, 매분 일일 초기화 |
| ShopService | 게임패스 조회, 골드 배수, ProcessReceipt(저장 확인 후 지급 완료) |
| CodexService | 도감 칸 보상, 업적 20개 평가(강화·배틀·접속 시) |
| LeaderboardService | OrderedDataStore 순위, 예산 확인, 퇴장 시+5분 주기 쓰기 |
| AdminService | `/관리` 명령, 감사 로그. `ADMIN_USER_IDS` 가 비면 비활성 |
| RateLimiter | 유틸 (생명주기 없음) |

`src/server/vendor/ProfileStore.luau` — 외부 원본(커밋 45c9847, Apache 2.0). 고치지 않는다.

### 클라이언트 (`src/client/controllers/`)

Sound → Effects → Feed → OddsTable → Battle → Shop → Collection → UI 순서로 초기화.
`ClientState` 가 서버가 보낸 데이터의 로컬 사본(표시 전용)을 들고 있다.

### 공유 (`src/shared/`)

- `Config/` — EnhanceTable, BattleConfig, EconomyConfig, Weapons, Products, Game, Achievements
- `Pure/` — EnhanceLogic, BattleLogic, Format (Roblox API 없음, 테스트 대상)
- `Types` (스키마 v3), `Remotes` (리모트 이름 한 곳), `Locale` (ko/en 각 163키)

### 기획상 정해졌지만 비어 있는 곳

지금 코드에는 무기 교체 기능이 없어서 도감 대부분을 채울 수 없다(새 기획의 검 보관함으로 해결 예정).
사운드 에셋, 무기 외형(3D 모델), 로비·경주 코스 공간이 비어 있다.

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
| 코드의 밸런스 수치는 아직 원안(프로토타입) 그대로 | 새 수치는 통합 기획서에 확정돼 있고, 구현 요청이 오면 그때 코드에 반영한다 |
| 채팅 명령어를 서버 런타임에 생성 | 코드로 관리하려고. **Studio 실동작 미확인** |

---

## 6. 이 클라우드 환경에서 검증하는 법

컨테이너는 세션마다 새로 만들어질 수 있다. 설치한 툴은 사라진다고 가정한다.

```bash
# 순수 로직 테스트·시뮬레이션용 Luau 실행기 (Lune 대체, 약 40초 빌드)
cargo build --release --manifest-path tools/luaurun/Cargo.toml
R=tools/luaurun/target/release/luaurun
$R tests/run.luau                         # 테스트 73개
$R tools/simulate_economy.luau            # 경제 시뮬레이션
$R --check $(git ls-files '*.luau')       # 전 파일 문법 검사

# 로블록스 툴체인 (crates.io 에서 빌드, 수 분)
cargo install rojo selene stylua --locked
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
