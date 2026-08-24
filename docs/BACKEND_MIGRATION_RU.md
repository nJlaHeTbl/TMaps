# Перенос базы TMaps без простоя

## Решение

Для TMaps подготовлена связка Cloudflare Workers + D1. Фронтенд остаётся на
бесплатном GitHub Pages. D1 использует SQLite-подобную базу, не взимает плату за
исходящий трафик базы и на бесплатном плане даёт 5 млн прочитанных строк,
100 тыс. записанных строк в сутки и 5 ГБ хранения. Workers Free даёт 100 тыс.
запросов в сутки.

Официальные условия:

- <https://developers.cloudflare.com/d1/platform/pricing/>
- <https://developers.cloudflare.com/workers/platform/pricing/>
- <https://developers.cloudflare.com/workers/platform/limits/>

Supabase пока оставлен рабочим. Его бесплатный план включает 500 МБ базы и
5 ГБ исходящего трафика, но проект может быть приостановлен после недели слабой
активности:

- <https://supabase.com/pricing>
- <https://supabase.com/docs/guides/platform/free-project-pausing>

## Что готово в коде

1. Flutter больше не привязан намертво к Supabase: сервер выбирается одной
   настройкой `TMAPS_API_BASE_URL`.
2. Новый Worker поддерживает точки, отзывы, голоса и заявки.
3. Запись ограничена по частоте, поля проверяются повторно на сервере.
4. Поддерживается Cloudflare Turnstile против ботов.
5. Есть закрытая страница `/admin/` с кнопками одобрения и отклонения.
6. Живой сайт без новой настройки продолжает использовать прежнюю базу.

## Порядок включения

### 1. Создать бесплатные ресурсы Cloudflare

Это действие выполняется только после подтверждения владельца аккаунта:

```powershell
cd backend
npx wrangler@latest login
npx wrangler@latest d1 create tmaps-community
```

Полученный `database_id` нужно заменить в `backend/wrangler.toml`.

### 2. Создать секреты

Сгенерировать два разных случайных значения длиной не менее 32 символов и
добавить их через команды, не записывая в файлы:

```powershell
npx wrangler@latest secret put ADMIN_TOKEN
npx wrangler@latest secret put RATE_LIMIT_SALT
```

Если включается Turnstile:

```powershell
npx wrangler@latest secret put TURNSTILE_SECRET
```

### 3. Создать таблицы и опубликовать API

```powershell
npx wrangler@latest d1 migrations apply tmaps-community --remote
npx wrangler@latest deploy
```

После публикации проверить `/api/health` и войти на `/admin/`.

### 4. Перенести данные

До переключения нужно выгрузить из Supabase четыре набора:

- `toilets`;
- `toilet_reports`;
- `place_votes`;
- `place_submissions`, включая ожидающие заявки.

Публичного ключа достаточно только для публичных таблиц. Ожидающие заявки
закрыты правилами безопасности, поэтому их нужно экспортировать из Table Editor
в Supabase Dashboard. Сервисный ключ нельзя вставлять в приложение, Git или
команды, которые могут попасть в историю.

После импорта сверяются количества строк и несколько случайных карточек. До
этой сверки Supabase не удаляется и остаётся резервным источником.

### 5. Переключить сборку сайта

Только после успешной проверки GitHub Pages собирается с параметром:

```powershell
flutter build web --release --base-href "/TMaps/" `
  --dart-define=TMAPS_API_BASE_URL=https://АДРЕС-WORKER
```

Сначала проверяются чтение точек, отправка тестовой заявки, её появление в
модерации, одобрение, отзыв и голос. Затем параметр добавляется в GitHub Actions.

## План отката

Если новый сервер даст ошибку, параметр `TMAPS_API_BASE_URL` убирается из
сборки. Следующая публикация автоматически вернёт приложение на Supabase. Данные
в старой базе не удаляются минимум две недели после успешного переключения.
