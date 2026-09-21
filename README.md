# 강화의 대장간 (ForgeFever)

무기를 골드로 강화하고(성공 / 유지 / 파괴), 같은 서버의 다른 플레이어와 배틀해
골드를 버는 캐주얼 강화 게임. 모바일 우선 UI, 한국어 기본 + 영어 지원.

모든 명칭·대사·캐릭터·UI 문구는 오리지널이다. 기존 서비스의 고유 명칭이나
이미지, 문구를 가져오지 않는다.

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

### 1-2. 패키지 설치

```bash
wally install       # Packages/ 와 ServerPackages/ 생성 (git 에는 올리지 않음)
```

> 이 단계에서 ProfileStore(세션 락이 걸린 데이터 저장 라이브러리)가 설치된다.
> 설치가 안 된 상태로 서버를 켜면 DataService 가 "`wally install` 을 실행하라"는
> 메시지를 남기고 멈추므로, 원인을 못 찾고 헤맬 일은 없다.

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

lune run tests/run          # 순수 로직 테스트 전체 실행
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
  services/              DataService, EnhanceService, BattleService, ...

src/client/              → StarterPlayerScripts
  init.client.luau       컨트롤러 부트스트랩
  controllers/           UIController, FeedController, SoundController

src/shared/              → ReplicatedStorage
  Types.luau             저장 스키마와 리모트 페이로드 타입
  Remotes.luau           리모트 이름 정의 (서버 Build / 클라 Get)
  Config/                밸런스 수치 (코드에 하드코딩 금지)
  Pure/                  Roblox API 를 쓰지 않는 순수 함수 (테스트 대상)

tests/                   Lune 테스트
tools/                   경제 시뮬레이션 등 개발 도구
docs/economy.md          경제 분석 결과와 밸런스 제안 (수치는 아직 안 바꿈)
```

### 지금 동작하는 것

- 접속하면 ProfileStore 로 내 데이터가 열리고, 없으면 기본값(골드 100)으로 시작한다.
- 화면 중앙의 강화 레벨, 하단의 강화 버튼, 성공/유지/파괴 확률과 비용이 보인다.
- 강화 버튼을 누르면 서버가 골드를 깎고 결과를 정해 돌려준다.
  파괴되면 파편을 받고, 방지권을 켜 두었으면 파괴가 막히며 방지권 1개가 소모된다.
- 우측(모바일은 상단, 접었다 펼칠 수 있음) 피드에 모루 영감의 대사가 한 줄씩 쌓인다.
- 결과에 맞는 연출이 나온다. 성공은 밝게 번쩍, 유지는 짧은 흔들림,
  파괴는 붉은 섬광과 조각이 흩어지는 연출, 20강 도달은 특수 연출.
- "확률표" 버튼으로 0~20 전 구간의 확률·비용·판매가를 언제든 볼 수 있다.
- "판매" 버튼으로 현재 무기를 팔 수 있다(확인 창을 한 번 거친다).
- 채팅 명령어로도 같은 일을 할 수 있다. 버튼과 완전히 같은 서버 경로를 탄다.
  - `/강화` (뒤에 `보호` 를 붙이면 방지권 사용), `/판매`, `/확률`, `/정보`, `/도움말`
- 15강 이상을 성공하면 서버의 모든 사람 채팅창에 알림이 간다.
- 하루 첫 접속에 출석 보상(연속 일수에 따라 100~1,000 골드), 15분마다 플레이 보상.
- 파괴로 모은 파편 50개를 방지권 1개로 바꿀 수 있다(상단 방지권 표시를 누르면 됨).
- "기록" 버튼에 도감 / 업적 / 랭킹이 탭으로 들어 있다. 도감은 무기 종류 × 레벨
  구간(5/10/15/20), 업적은 20개, 랭킹은 최고 강화 레벨과 배틀 레이팅 상위 50명.
- "상점" 버튼으로 게임패스와 골드 팩을 살 수 있다. **상품 ID 를 넣기 전에는
  목록이 비어 있고, 게임에는 아무 영향이 없다.**
- "배틀" 버튼으로 같은 서버의 상대를 골라 도전할 수 있다(또는 아무나 매칭).
  상대는 15초 안에 수락/거절하고, 무응답은 거절로 친다. 이기면 골드와 레이팅을 얻고
  져도 참가 보상 5골드는 받는다. **배틀로 무기가 깨지거나 레벨이 내려가지는 않는다.**

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
| 7 | 라이브 운영, 다국어, 튜토리얼, 출시 준비 | 예정 |

---

## 7. 확인이 필요한 것 (개발자 작업)

- [ ] `rokit.toml` 의 툴 버전 검증 (위 1-1 참고)
- [ ] **텍스트 명령어 동작 확인** — 서버에서 런타임에 만든 `TextChatCommand` 가
      정상 등록되는지 Studio 에서 한 번 확인. 공식 예제는 Studio 에서 미리 만들어 둔
      인스턴스를 쓰는 형태라 이 부분만 문서로 확정하지 못했다. 동작하지 않으면
      `ChatCommandService` 의 주석에 대안이 적혀 있다.
- [ ] 게임 설정의 채팅 버전이 **TextChatService** 인지 확인 (레거시 채팅이면
      명령어가 등록되지 않고 서버 로그에 경고가 남는다)
- [ ] `src/shared/Config/Game.luau` 의 `ADMIN_USER_IDS` 에 본인 UserId 입력
- [ ] `src/shared/Config/Products.luau` 의 게임패스 / 개발자 상품 ID 입력
      (상품 생성 후. ID 가 0 이면 상점에 노출되지 않는다)
- [ ] 게임 설정에서 **Studio Access to API Services** 활성화

---

## 8. 수익화 정책 메모

- 기본 설계는 **확률 결과 자체를 Robux 로 팔지 않는 방향**이다. 게임패스는
  편의/꾸미기, 개발자 상품은 골드 팩과 방지권 묶음까지만.
- Robux 로 확률형 결과를 직접 사는 상품을 넣으려면 로블록스의 유료 랜덤 아이템
  규정(구매 전 확률 공개)과 국내 확률형 아이템 표시 규정을 먼저 확인해야 한다.
  넣기 전에 반드시 개발자 승인을 받을 것.
- 확률표는 상품 여부와 관계없이 **강화 화면에서 항상 열람 가능**해야 한다.
