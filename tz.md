Часть 1: Техническое задание на разработку Бэкенда (FastAPI)
1. Общие положения и архитектура
Цель MVP: Обеспечить базовый обмен текстовыми сообщениями в реальном времени между пользователями, аутентификацию и хранение истории.

Архитектурный стиль: Монолитное приложение с чётким разделением на слои (API, Сервисы, Репозитории).
Протокол реального времени: WebSocket (нативный, через FastAPI WebSocket или Socket.IO для упрощения управления комнатами ).
Аутентификация: JWT (Access Token). Токен передаётся в заголовке Authorization для HTTP-запросов и в query-параметре или первом сообщении для WebSocket-соединения.

2. Стек технологий и зависимости
Язык: Python 3.11+

Фреймворк: FastAPI

ORM: SQLAlchemy 2.0 (async) + Alembic (миграции).

База данных: PostgreSQL (драйвер asyncpg).

Валидация: Pydantic v2.

Безопасность: passlib[bcrypt] (хеширование паролей), python-jose (JWT).

Дополнительно: redis (опционально, для кеширования счетчиков непрочитанных или Pub/Sub при масштабировании, но для MVP можно опустить и хранить статус в БД).

3. Модель данных (Схема БД PostgreSQL)
Необходимо реализовать следующие таблицы (все с полями created_at, updated_at):

3.1. users
id (UUID, PK)

username (String, Unique, Index) — уникальный идентификатор (никнейм).

email (String, Unique, Index) — для входа.

password_hash (String) — хеш пароля.

display_name (String, Nullable) — отображаемое имя.

avatar_url (String, Nullable) — ссылка на аватар (для MVP можно заглушку).

is_online (Boolean, default=False) — статус присутствия.

last_seen (DateTime, Nullable).

3.2. chats (Диалоги/Группы)
id (UUID, PK)

type (Enum: private, group) — для MVP только private (личные сообщения) и group (базовые группы).

title (String, Nullable) — для групп.

created_by (UUID, FK -> users.id).

3.3. chat_members (Связь пользователей и чатов)
chat_id (UUID, FK -> chats.id, PK part 1)

user_id (UUID, FK -> users.id, PK part 2)

joined_at (DateTime)

role (Enum: member, admin) — для MVP достаточно member.

3.4. messages
id (UUID, PK)

chat_id (UUID, FK -> chats.id, Index)

sender_id (UUID, FK -> users.id)

content (Text) — текст сообщения.

created_at (DateTime, Index) — время отправки.

is_read (Boolean, default=False) — флаг прочтения (для статуса «прочитано»).

reply_to_id (UUID, Nullable, FK -> messages.id) — для ответов (опционально для MVP).

Индексы:

(chat_id, created_at DESC) — для быстрой пагинации истории .

4. Функциональные требования (API Endpoints)
4.1. Аутентификация (/api/v1/auth)
POST /register

Вход: username, email, password.

Выход: access_token, token_type, user (объект).

Ошибки: 400 (email занят), 422 (валидация).

POST /login

Вход: email, password (OAuth2PasswordRequestForm).

Выход: access_token, token_type.

GET /me

Заголовок: Authorization: Bearer <token>.

Выход: Профиль текущего пользователя.

4.2. Пользователи (/api/v1/users)
GET /search?q={query}

Поиск пользователей по username или email для создания чата.

GET /{user_id}

Получение публичного профиля.

4.3. Чаты (/api/v1/chats)
GET /

Список чатов текущего пользователя (с последним сообщением и счетчиком непрочитанных).

POST /

Создание чата.

Вход: type (private или group), participant_ids (список UUID), title (если группа).

Логика: Если private и чат с таким пользователем уже существует — вернуть существующий.

GET /{chat_id}/messages

Пагинация: ?limit=50&before={message_id} (Cursor-based, не offset) .

Выход: Список сообщений (от старых к новым или наоборот, в зависимости от реализации скролла).

4.4. WebSocket (/ws/chat/{chat_id})
Аутентификация: Передача JWT в query-параметре (?token=...) или в заголовке Sec-WebSocket-Protocol. При невалидном токене — закрытие соединения с кодом 1008 (Policy Violation) .

Логика подключения:

Проверка, что user_id является участником chat_id.

Добавление сокета в ConnectionManager (менеджер комнат).

Входящие события (от клиента):

send_message: { content: string, temp_id: string }.

read_receipt: { message_id: string } (отметка о прочтении).

typing: { is_typing: boolean }.

Исходящие события (от сервера):

new_message: { id, chat_id, sender, content, created_at, temp_id } (рассылка всем участникам комнаты).

user_typing: { user_id, is_typing }.

message_read: { message_id, user_id }.

user_presence: { user_id, status: online/offline }.

5. Нефункциональные требования и безопасность
Валидация: Все входящие данные проверяются через Pydantic. Длина сообщения ограничена (например, 4096 символов).

CORS: Настроить разрешенные origins (localhost для разработки, домен фронтенда для продакшена).

WebSocket Lifecycle: Обязательная обработка WebSocketDisconnect и очистка комнат в finally блоке, чтобы избежать утечек памяти .

Безопасность: Пароли хранятся только в виде bcrypt-хеша. JWT имеет время жизни (например, 30 минут для access, с возможностью refresh в будущем, но в MVP можно ограничиться 24 часами для простоты).

Обработка ошибок: Глобальный exception handler для возврата JSON с detail вместо HTML-страниц.