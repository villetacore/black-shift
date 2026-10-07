# Участие в разработке

## Окружение

- Erlang/OTP 27+ и Elixir 1.18+ (на Windows: `scripts/install-beam.ps1` ставит их локально в `build/deps`);
- Rust stable (MSVC на Windows);
- Visual Studio C++ tools и CMake ≥ 3.24;
- Qt ≥ 6.4 с модулями Widgets, Network, OpenGL, OpenGLWidgets.

Подробнее о сборке — в [README](README.md#сборка-из-исходников).

## Перед pull request

```sh
cd server && mix format && mix test --warnings-as-errors
cd client/core && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test
```

C++ форматируется по `.clang-format`. Для изменений клиента на Windows дополнительно:

```powershell
.\scripts\build.ps1 -TestClient
```

Нативный тест открывает окно игры и подключается к серверу. Не сворачивайте и не перекрывайте окно во время теста: потеряв фокус, игра отпускает управление, и проверка ввода не пройдёт.

## Правила

- Сервер авторитетен: клиент только отображает снимки и отправляет ввод.
- Изменение формата сообщений — это изменение протокола: обновите `docs/protocol.md`, сервер и клиент вместе.
- Изменение `server/priv/maps/*.json` требует пересборки сервера (карта встраивается при компиляции).
- Новые игровые константы — именованные атрибуты модуля, а не числа в коде.
- Запишите заметное изменение в раздел `[Unreleased]` файла [CHANGELOG.md](CHANGELOG.md).

## Выпуск версии

1. Поднимите версию в `CMakeLists.txt`, `server/mix.exs`, `client/core/Cargo.toml`.
2. Перенесите `[Unreleased]` в новый раздел `CHANGELOG.md`.
3. Создайте и отправьте тег: `git tag v0.4.0 && git push origin v0.4.0`.

Workflow `Release` проверит, что тег совпадает с версией, и соберёт:

- архивы игры для Windows x64, Linux x64 (AppImage) и macOS arm64;
- Docker-образ сервера `ghcr.io/<owner>/<repo>-server` для `linux/amd64` и `linux/arm64` с тегом версии и `latest`.

Затем он опубликует релиз на GitHub с заметками из `CHANGELOG.md`. Тег с суффиксом (`v0.4.0-rc1`) выходит как pre-release без тега `latest`.

## CI

На каждый push и pull request (`.github/workflows/ci.yml`):

- тесты и проверка форматирования сервера;
- `fmt`, `clippy` и тесты Rust;
- сборка клиента на Windows, Linux и macOS;
- сборка Docker-образа и проверка, что сервер в контейнере отвечает по протоколу.
