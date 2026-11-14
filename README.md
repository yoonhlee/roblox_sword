# 강화의 대장간 (ForgeFever)

검을 골드로 강화하고(성공 / 유지 / 실패), 그 검을 들고 추격 생존 경주를 달려 골드를 버는
게임. 모바일 우선 UI, 한국어 기본 + 영어 지원.

> **기획 기준은 [docs/통합-기획서.md](docs/통합-기획서.md)**, 지금 코드 상태는 `CLAUDE.md` 4절이다.
> 지금 코드에는 강화(2구간), 검 보관함·뽑기·도감, 추격 생존 경주와 로비 트레드밀, 방지권 상품 틀(ID·확률은 미정이라
> 상점에는 아직 안 보인다)까지 들어 있다. Studio 실동작은 아직 확인 전이다.
> 이 README 의 아래 내용 중 "2인 테스트", "출시 체크리스트", "수익화 정책 메모"에는 옛 기획(배틀, 게임패스,
> 골드 팩) 설명이 남아 있다. 다르면 통합 기획서를 따른다.

모든 명칭·대사·캐릭터·UI 문구는 오리지널이다. 기존 서비스의 고유 명칭이나
이미지, 문구를 가져오지 않는다.

---

## 0. 바로 해 보기

터미널 없이 **Roblox Studio 하나로** 게임을 켜 볼 수 있다.

1. 이 저장소의 **`ForgeFever.rbxlx`** 를 내려받는다
   (GitHub 에서 파일을 클릭 → 오른쪽 위 **Download raw file**)
2. 더블클릭하면 Roblox Studio 가 열린다
3. 상단 **Play** 버튼(▶)을 누른다

자세한 절차와 확인할 목록, 문제가 생겼을 때 대처법은
**[docs/시작하기.md](docs/시작하기.md)** 에 정리해 뒀다.

> `ForgeFever.rbxlx` 는 `src/` 를 Rojo 로 빌드한 **특정 시점의 사진**이다.
> 코드를 고쳤다면 `rojo build -o ForgeFever.rbxlx` 로 다시 만들어야 반영된다.
> 계속 개발할 때는 아래 Rojo 연결 방식을 쓴다.

---

## 1. 개발 환경 준비

### 1-1. 툴 설치

툴 버전은 [Rokit](https://github.com/rojo-rbx/rokit)으로 고정한다. Rokit 설치 후
저장소 루트에서:

```bash
rokit install       # rokit.toml 의 rojo / wally / selene / stylua / lune 설치
```

> `rokit.toml` 의 버전 문자열은 아직 온라인 검증을 하지 못했다(**확인 필요**).
> 설치가 실패하면 `rokit add rojo-rbx/rojo` 처럼 버전 없이 추가해 최신 릴리스로
> 다시 고정하고 `rokit.toml` 을 커밋해 줘.

### 1-2. 패키지 설치 (지금은 필요 없음)

현재 외부 패키지 의존성이 없다. 데이터 저장 라이브러리인 **ProfileStore 는
`src/server/vendor/` 에 파일로 포함**되어 있어서 Wally 없이도 동작한다
(출처와 라이선스는 `src/server/vendor/README.md` 참고).

나중에 패키지를 추가하면 그때 `wally install` 을 실행한다.

### 1-3. Selene 표준 라이브러리 생성

```bash
selene generate-roblox-std    # roblox.toml 생성 (.gitignore 처리되어 있음)
```

---

## 2. Studio 에 연결하는 방법

Claude Code 는 Studio 를 직접 조작하지 않는다. **코드는 전부 이 저장소의 파일이고,
Studio 로는 Rojo 가 밀어 넣는다.**

1. Roblox Studio 를 열고 새 Baseplate 를 만든다.
2. Studio 의 **Plugins → Manage Plugins** 에서 **Rojo** 플러그인을 설치한다.
   (또는 터미널에서 `rojo plugin install`)
3. 터미널에서 서버를 켠다.

   ```bash
   rojo serve
   ```

4. Studio 의 Rojo 플러그인 창에서 **Connect** 를 누른다.
   (기본 주소 `localhost:34872`)
5. 연결되면 `src/` 의 내용이 아래처럼 들어간다.

   | 파일시스템 | Studio |
   | --- | --- |
   | `src/server/` | `ServerScriptService/Server` (Script) |
   | `src/client/` | `StarterPlayer/StarterPlayerScripts/Client` (LocalScript) |
   | `src/shared/` | `ReplicatedStorage/Shared` (Folder) |
   | `Packages/` | `ReplicatedStorage/Packages` |
   | `ServerPackages/` | `ServerStorage/ServerPackages` |

6. 파일을 저장하면 Studio 에 바로 반영된다. **Studio 안에서 스크립트를 직접
   수정하지 말 것** — 다음 동기화에서 덮어써진다.

### 플레이스 파일만 만들고 싶을 때

```bash
rojo build -o ForgeFever.rbxlx
```

### DataStore 를 Studio 에서 테스트하려면

게임 설정 → **Security → Enable Studio Access to API Services** 를 켠다.
Studio 플레이테스트는 `ForgeFever_DEV` 스토어를 쓰고, 라이브는 `ForgeFever_PROD`
를 쓴다(`src/shared/Config/Game.luau`). 두 데이터는 절대 섞지 않는다.

---

## 3. 자주 쓰는 명령어

```bash
rojo serve                  # Studio 동기화 서버
rojo build -o build.rbxlx   # 플레이스 파일 빌드
wally install               # 패키지 설치

lune run tests/run          # 순수 로직 테스트 전체 실행 (154개)
lune run tools/simulate_economy   # 경제 시뮬레이션
stylua src tests tools      # 포맷
selene src tests tools      # 린트
```

---

## 4. 2인 로컬 서버 테스트 절차

배틀과 데이터 저장은 플레이어가 둘 이상이어야 제대로 확인된다.

1. `rojo serve` 로 Studio 에 동기화한다.
2. Studio 상단 **Test** 탭 → **Clients and Servers** 에서
   **Players = 2**, 모드는 **Local Server** 로 설정한다.
3. **Start** 를 누르면 서버 창 1개 + 클라이언트 창 2개가 열린다.
4. 확인할 것
   - 각 클라이언트가 서로 다른 프로필을 로드하는지 (골드/레벨이 독립적인지)
   - 한쪽에서 강화해도 다른 쪽 화면이 바뀌지 않는지
   - 강화 버튼을 연타해도 요청이 한 번에 하나만 처리되는지 (버튼이 잠김)
   - 채팅창에 `/강화` 를 쳤을 때 버튼과 똑같이 동작하는지
   - 한쪽이 15강 이상을 성공했을 때 다른 쪽 채팅창에도 알림이 뜨는지
   - 창 크기를 좁게 줄였을 때(모바일 흉내) 피드가 위로 올라가고 접히는지
   - 배틀 도전 → 수락/거절/15초 무응답이 의도대로 동작하는지
   - 배틀 뒤에도 양쪽 무기 레벨이 그대로인지 (배틀은 레벨을 건드리지 않는다)
   - **Shutdown** 으로 서버를 강제 종료한 뒤 다시 들어갔을 때 데이터가 남아 있는지
5. 서버 창의 Output 에 아래 로그가 찍히는지 본다.
   - `[DataService] 스토어 "ForgeFever_DEV" 사용`
   - `[Bootstrap] 서비스 10개 시작 완료`
   - 강화할 때마다 `[Economy] ... gold sink -10 (enhance_cost) → ...`
     와 `[Enhance] ... +0 → success (비용 10)` 형태의 기록

---

## 5. 폴더 구조

```
default.project.json     Rojo 매핑
rokit.toml               툴 버전 고정
wally.toml               패키지 의존성
selene.toml / stylua.toml

src/server/              → ServerScriptService
  init.server.luau       서비스 부트스트랩 (Init → Start 순서 보장)
  services/              DataService, EnhanceService, RaceService, ShopService, ...

src/client/              → StarterPlayerScripts
  init.client.luau       컨트롤러 부트스트랩
  controllers/           UIController, LobbyController, RaceController, ShopController, ...

src/shared/              → ReplicatedStorage
  Types.luau             저장 스키마와 리모트 페이로드 타입
  Remotes.luau           리모트 이름 정의 (서버 Build / 클라 Get)
  Config/                밸런스 수치 (코드에 하드코딩 금지)
  Pure/                  Roblox API 를 쓰지 않는 순수 함수 (테스트 대상)

tests/                   Lune 테스트
tools/                   경제 시뮬레이션, Luau 테스트 실행기(luaurun) 등 개발 도구
docs/기획서.md            게임 기획 기준 문서 + 제안·승인 기록
docs/원본-지시서.md        처음 받은 지시서 원문
docs/economy.md          경제 분석 결과와 밸런스 제안 (수치는 아직 안 바꿈)
docs/시작하기.md          Studio 에서 실행하는 법
CLAUDE.md                Claude 가 다음 세션에도 이어서 일하기 위한 작업 메모
```

### 지금 동작하는 것

Studio 에서 확인하는 절차는 [docs/시작하기.md](docs/시작하기.md) 2절에 있다. (아래는 코드에 들어 있는 것이고,
Studio 실동작은 아직 확인 전이다.)

- 강화: 0~9강은 실패 없음, 10~19강은 실패하면 10강으로 돌아가고 파편을 받는다.
  비용은 100 × (1 + 2^레벨) × (가진 검 수)^1.1.
- 방지권을 켜 두면 2구간 실패가 유지로 바뀌고, 화면의 확률도 그렇게 바뀐다(실패 0%).
- "확률표": 0~20강의 최종 확률(이벤트·방지권 반영)과 비용.
- "검": 가진 검 목록과 착용, 소지 상한 구매 + 새 검 뽑기(가격과 내 기준 확률표를 먼저 보여 준다).
- "기록": 도감(검마다 최고 레벨과 5·10·15·20강 기념) / 랭킹(최고 강화) / 설정(소리·언어).
- 채팅 명령어 `/강화 [보호]`, `/확률`, `/정보`, `/도움말`. 15강 이상 성공은 서버 전체 알림.
- 검 이름 짓기(로블록스 필터를 통과한 이름만), 출석·15분 플레이 보상, 첫 접속 안내.
- 로비: 접속하면 블록으로 지은 로비에 선다. "대장간 접기"로 강화 패널을 접고 돌아다닐 수 있다.
- 트레드밀: 로비 한쪽의 초록 발판 위에 있으면 20초마다 100골드.
- 경주: "경주 매칭" → 10초 안에 출발선 → 뒤에서 점점 빨라지는 추격자(빨간 벽)에게 잡히면 탈락.
  잡히는 순간 `착용 검 레벨의 강화 비용 × 배율 × 달린 비율` 만큼 골드를 받는다. 탈락 후 관전하거나 "로비로".
  거리는 서버가 계산한다(클라이언트가 보낸 값은 쓰지 않는다).
- "상점": 방지권 상품 3종(확정 1개 / 확정 묶음 / 확률형 + 천장 포인트)과 파편 뽑기.
  상품 ID·개수·확률이 아직 미정이라 **지금은 비어 보인다**. `src/shared/Config/Products.luau` 를 채우면 나타난다.

### 코드 규칙

- 모든 Luau 파일 상단에 `--!strict`
- 밸런스 수치는 `src/shared/Config/` 에 데이터로. 로직은 읽기만 한다.
- 확률 계산·골드 증감·레벨 변경·배틀 결과는 **서버에서만**. 클라이언트가 보낸
  레벨/골드/결과 값은 신뢰하지 않는다.
- 서버 함수는 입력 타입 검증부터. 실패는 에러 대신 `{ ok = false, reason = "..." }`.
- 사람이 읽는 문자열은 LocalizationTable 키로. 코드에 표시용 한국어를 박지 않는다.

---

## 6. 진행 상황

| Phase | 내용 | 상태 |
| --- | --- | --- |
| 0 | 환경 세팅, 폴더 구조, 빈 서비스 부트스트랩 | 완료 |
| 1 | DataService(ProfileStore), EnhanceLogic + 테스트, EnhanceService, 최소 UI | 완료 |
| 2 | 결과 피드, 연출, 확률표 화면, 텍스트 명령어, 모바일 대응 | 완료 |
| 3 | 배틀 (도전/수락, BattleLogic, 보상·레이팅, 어뷰징 방지) | 완료 |
| 4 | 경제 + 시뮬레이션 (`tools/simulate_economy.luau`) | 완료 |
| 5 | 수익화 (게임패스/개발자 상품, ProcessReceipt) | 완료 |
| 6 | 도감 / 업적 / 랭킹 | 완료 |
| 7 | 라이브 운영, 다국어, 튜토리얼, 출시 준비 | 완료 |

---

## 7. 라이브 운영

게임을 다시 올리지 않고 이벤트를 켜고 끌 수 있다. 설정은 DataStore 키 하나에
들어 있고 모든 서버가 60초마다 읽는다.

### 관리자 명령어

먼저 `src/shared/Config/Game.luau` 의 `ADMIN_USER_IDS` 에 본인 UserId 를 넣어야 한다.
목록이 비어 있으면 아무도 관리자 명령을 쓸 수 없다(기본값이 "아무도 안 됨"이다).

채팅창에 입력한다.

```
/관리 도움말
/관리 골드 <닉네임> <양>          골드 지급(음수면 회수)
/관리 레벨 <닉네임> <레벨>         강화 레벨 설정
/관리 방지권 <닉네임> <개수>
/관리 차단 <닉네임> <시간>         시간 단위, 0 이면 해제
/관리 정보 <닉네임>                그 사람 데이터 조회
/관리 점검 켜기 | 끄기              점검 모드(강화·배틀 차단 + 안내 배너)
/관리 이벤트 <성공확률+%p> <지속분>  확률 버프 이벤트 시작
/관리 이벤트끄기
/관리 이상기록                     골드 급증 탐지 기록
/관리 기록                         관리자 행동 기록
```

모든 관리자 행동은 서버 로그와 메모리에 남는다. 확률 버프는 성공 확률에만 더하고
**파괴 확률은 절대 건드리지 않는다**. 적용된 최종 확률은 강화 화면에 항상 표시된다.

---

## 8. 출시 전 체크리스트

코드 쪽은 끝났고, 아래는 개발자가 로블록스 사이트에서 해야 하는 일이다.

- [ ] 게임 설정에서 **Studio Access to API Services** 허용 (DataStore 테스트용)
- [ ] 게임 설정의 채팅 버전이 **TextChatService** 인지 확인
- [ ] `src/shared/Config/Game.luau` 의 `ADMIN_USER_IDS` 에 본인 UserId 입력
- [ ] 게임패스·개발자 상품을 만들고 `src/shared/Config/Products.luau` 에 ID 입력
      (ID 가 0 이면 상점에 노출되지 않으므로, 넣기 전에도 게임은 정상 동작한다)
- [ ] 스토어 이름 확인 — Studio 는 `ForgeFever_DEV`, 라이브는 `ForgeFever_PROD`
      (코드가 자동으로 나눈다. 바꾸고 싶으면 `Config/Game.luau`)
- [ ] 경험 설문(콘텐츠 성숙도) 작성
- [ ] 아이콘·썸네일·설명(한/영) 등록 — **전부 오리지널 에셋으로**
- [ ] 비공개 테스트: 친구 5명 이상 동시 접속으로 배틀과 저장 검증
- [ ] 서버 강제 종료 후 데이터가 남아 있는지 확인
- [ ] 확률표 화면이 열리는지 확인
- [ ] `lune run tools/simulate_economy` 결과를 보고 밸런스 최종 결정
      (`docs/economy.md` 참고)

---

## 9. 아직 확정하지 못한 것

출시 체크리스트(8절)와 별개로, **내가 문서만으로 100% 확정하지 못해 Studio 에서
한 번 확인이 필요한 부분**이다.

- [ ] **텍스트 명령어 등록 방식** — 서버 스크립트가 런타임에 `TextChatCommand` 를
      만들어 `TextChatService` 아래에 붙인다. 공식 예제는 Studio 에서 미리 만들어 둔
      인스턴스를 `WaitForChild` 로 찾는 형태여서, 런타임 생성이 동작하는지는
      확인이 필요하다. 동작하지 않으면 Studio 의 `TextChatService` 아래에
      `TextChatCommand` 를 직접 만들고 이름을 `ChatCommandService` 의
      `COMMANDS` 목록과 맞추면 된다(주석에 적어 뒀다).
- [ ] **`rokit.toml` 의 툴 버전** — 이 환경에서 릴리스 목록을 조회하지 못해
      버전 문자열을 검증하지 못했다. `rokit install` 이 실패하면
      `rokit add rojo-rbx/rojo` 처럼 버전 없이 추가해 최신으로 고정하면 된다.
- [ ] **화면과 저장의 실제 동작** — 순수 로직은 59개 테스트로 검증했지만,
      UI 와 DataStore 는 Roblox Studio 밖에서 실행할 방법이 없어 한 번도
      실제로 돌려 보지 못했다. 4절의 2인 로컬 서버 절차로 확인해 줘.

---

## 10. 수익화 정책 메모

- 기본 설계는 **확률 결과 자체를 Robux 로 팔지 않는 방향**이다. 게임패스는
  편의/꾸미기, 개발자 상품은 골드 팩과 방지권 묶음까지만.
- Robux 로 확률형 결과를 직접 사는 상품을 넣으려면 로블록스의 유료 랜덤 아이템
  규정(구매 전 확률 공개)과 국내 확률형 아이템 표시 규정을 먼저 확인해야 한다.
  넣기 전에 반드시 개발자 승인을 받을 것.
- 확률표는 상품 여부와 관계없이 **강화 화면에서 항상 열람 가능**해야 한다.
