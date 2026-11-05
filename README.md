# Artyom Messenger Backend

MVP-бэкенд мессенджера на FastAPI: регистрация/вход по JWT, личные и групповые чаты, история сообщений с cursor-based пагинацией, обмен сообщениями и статусами в реальном времени через WebSocket.

## Стек

- Python 3.11+
- FastAPI + Pydantic v2
- SQLAlchemy 2.0 (async) + Alembic
- PostgreSQL + asyncpg
- passlib[bcrypt] + python-jose (JWT)
- WebSocket (нативные комнаты через `ConnectionManager`)

## Структура

```
app/
  api/            HTTP-роуты и зависимости
  core/           конфигурация, БД, безопасность
  models/         ORM-модели SQLAlchemy
  repositories/   доступ к данным
  schemas/        Pydantic-схемы
  services/       бизнес-логика
  ws/             WebSocket-менеджер комнат и обработчики
alembic/          миграции
tests/            интеграционные тесты (SQLite, без внешней БД)
```

## Быстрый старт

1. Создайте окружение и установите зависимости:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

2. Создайте `.env` по примеру:

```powershell
Copy-Item .env.example .env
```

Обязательно задайте свой `SECRET_KEY`. Порт PostgreSQL задаётся переменной `POSTGRES_PORT`, и он должен совпадать с портом в `DATABASE_URL`:

```env
POSTGRES_PORT=5432
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/artyom
```

3. Поднимите PostgreSQL (Docker Desktop должен быть запущен):

```powershell
docker compose up -d db
docker compose ps
```

4. Примените миграции:

```powershell
alembic upgrade head
```

5. Запустите приложение:

```powershell
.\run.ps1
```

Скрипт сам создаст `.env` при необходимости, выберет свободный порт начиная с `8000` и выведет адреса API и Swagger. Если PowerShell блокирует скрипты:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run.ps1
```

Явно задать порт можно так:

```powershell
.\run.ps1 -Port 8001
```

Или запустить напрямую:

```powershell
uvicorn app.main:app --reload --port 8001
```

Документация: `http://127.0.0.1:<выбранный порт>/docs`, health-check: `GET /health`.

## Если порты уже заняты

Проверить занятость порта:

```powershell
Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
```

Если `5432` занят, выберите свободный порт (например `5434`) и синхронно поменяйте его в `.env`:

```env
POSTGRES_PORT=5434
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5434/artyom
```

Затем пересоздайте контейнер, чтобы применился новый проброс порта:

```powershell
docker compose up -d db
```

Если `8000` занят, запустите API на другом порту:

```powershell
uvicorn app.main:app --reload --port 8001
```

Все примеры ниже используют `8000`; замените его на выбранный порт.

## Частые проблемы

- **`failed to connect to the docker API`** — запустите Docker Desktop и дождитесь статуса `Engine running`.
- **`database is locked` в тестах** — тесты используют отдельную SQLite-базу; повторный запуск создаёт её заново. Убедитесь, что не запущено несколько `pytest` одновременно.
- **`password authentication failed`** — проверьте, что `POSTGRES_PORT`, логин и пароль в `DATABASE_URL` совпадают с `docker-compose.yml`.
- **Изменения схемы не видны** — выполните `alembic upgrade head` и проверьте версию через `alembic current`.
- **WebSocket-события не доходят между клиентами** — запускайте один worker: комнаты хранятся в памяти процесса. Для нескольких реплик нужен Redis Pub/Sub.

## API

Все HTTP-эндпоинты, кроме регистрации и входа, требуют заголовок:

```
Authorization: Bearer <access_token>
```

| Метод | Путь | Описание |
| --- | --- | --- |
| POST | `/api/v1/auth/register` | Регистрация, возвращает токен и профиль |
| POST | `/api/v1/auth/login` | Вход через OAuth2 form (`username` = email) |
| GET | `/api/v1/auth/me` | Текущий профиль |
| GET | `/api/v1/users/search?q=` | Поиск пользователей по username/email/display_name |
| GET | `/api/v1/users/{user_id}` | Публичный профиль |
| GET | `/api/v1/chats` | Чаты пользователя с последним сообщением и unread_count |
| POST | `/api/v1/chats` | Создание личного или группового чата |
| GET | `/api/v1/chats/{chat_id}` | Один чат |
| GET | `/api/v1/chats/{chat_id}/messages?limit=50&before=<message_id>` | История (cursor-based, от старых к новым) |

`unread_count` считается по сообщениям других участников с `is_read = false`.

## WebSocket

Подключение:

```
ws://127.0.0.1:8000/ws/chat/{chat_id}?token=<access_token>
```

Если токен невалиден, пользователь не участник чата или соединение просрочено, сервер закрывает соединение с кодом `1008`.

Клиент отправляет JSON-события:

```json
{"type": "send_message", "content": "Привет", "temp_id": "client-1"}
{"type": "read_receipt", "message_id": "uuid"}
{"type": "typing", "is_typing": true}
```

Сервер присылает:

```json
{
  "type": "new_message",
  "id": "uuid",
  "chat_id": "uuid",
  "sender": {"id": "uuid", "username": "alice", "display_name": "Alice", "is_online": true},
  "content": "Привет",
  "created_at": "2026-11-03T15:00:00+00:00",
  "is_read": false,
  "reply_to_id": null,
  "temp_id": "client-1"
}
{"type": "message_read", "chat_id": "uuid", "message_id": "uuid", "user_id": "uuid", "is_read": true}
{"type": "user_typing", "chat_id": "uuid", "user_id": "uuid", "is_typing": true}
{"type": "user_presence", "chat_id": "uuid", "user_id": "uuid", "status": "online"}
{"type": "error", "detail": "Invalid event"}
```

## Тесты

```bash
pip install -r requirements-dev.txt
pytest
```

Тесты используют временную SQLite-базу и не требуют запущенного PostgreSQL.

## Особенности MVP

- Приватный чат идемпотентен: повторное создание с тем же пользователем возвращает существующий чат.
- Пароли хранятся только в bcrypt-хеше, JWT живёт 24 часа по умолчанию (`ACCESS_TOKEN_EXPIRE_MINUTES`).
- Ограничение длины сообщения — 4096 символов (`MAX_MESSAGE_LENGTH`).
- `is_read` в MVP — единый флаг сообщения; отдельные «прочитано каждым» для групп не реализованы.
- Комнаты WebSocket хранятся в памяти процесса; для нескольких реплик нужен Redis Pub/Sub.
