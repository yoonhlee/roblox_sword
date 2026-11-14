# luaurun

Lune 을 설치할 수 없는 환경(클라우드 세션 등)에서 순수 로직 테스트를 돌리기 위한
최소 Luau 실행기. 개발자 PC 에서는 `lune run tests/run` 을 쓰면 되고 이건 필요 없다.

```bash
cargo build --release --manifest-path tools/luaurun/Cargo.toml
tools/luaurun/target/release/luaurun tests/run.luau
tools/luaurun/target/release/luaurun tools/simulate_economy.luau
tools/luaurun/target/release/luaurun --check $(git ls-files '*.luau')
```

Roblox API(`game`, `Instance` 등)는 없으므로 `src/shared/Pure`, `src/shared/Config`,
`RateLimiter` 처럼 Roblox 에 의존하지 않는 모듈만 실행할 수 있다. 서버/클라이언트
코드는 `--check` 로 문법만 검사한다.
