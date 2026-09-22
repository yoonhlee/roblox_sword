# vendor

외부 라이브러리를 그대로 넣어 둔 곳이다. **이 폴더의 파일은 직접 고치지 않는다.**

## ProfileStore.luau

- 출처: https://github.com/MadStudioRoblox/ProfileStore (MAD STUDIO, loleris)
- 가져온 커밋: `45c9847`
- 라이선스: Apache License 2.0 (`ProfileStore-LICENSE.txt`)
- 수정 사항: 없음 (원본 그대로)

세션 락이 걸린 DataStore 저장 라이브러리다. 같은 플레이어의 데이터가
두 서버에서 동시에 열리는 것을 막아 주며, 이게 아이템 복사 버그를 막는 핵심이다.

### 왜 Wally 대신 파일로 넣었나

Wally 패키지(`lm-loleris/profilestore`)로 받아도 되지만, 그러면 게임을 켜기 위해
Wally 설치와 `wally install` 실행이 반드시 필요해진다. 공식 문서도 "GitHub 에서
받아 ServerScriptService 에 넣기"를 설치 방법 중 하나로 안내하고 있어서,
설정 단계를 줄이려고 파일로 포함했다.

Wally 로 관리하고 싶다면 `wally.toml` 의 주석을 풀고 이 폴더를 지우면 된다.
`DataService` 는 두 위치를 모두 찾아본다.

### 업데이트하는 법

```bash
git clone --depth 1 https://github.com/MadStudioRoblox/ProfileStore /tmp/profilestore
cp /tmp/profilestore/ProfileStore.luau src/server/vendor/ProfileStore.luau
```

위 "가져온 커밋"도 함께 갱신할 것.
