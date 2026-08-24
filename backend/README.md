# TMaps Community API

Подготовленный бесплатный backend для пользовательских точек, отзывов,
голосов и модерации TMaps. Он рассчитан на Cloudflare Workers + D1 и пока не
включён на опубликованном сайте: до завершения переноса приложение продолжает
безопасно пользоваться Supabase.

## Что уже есть

- серверная проверка всех пользовательских полей;
- лимиты частоты заявок, отзывов и голосов по IP;
- необязательная защита Cloudflare Turnstile;
- разрешённые домены CORS;
- закрытые методы модерации;
- страница модератора `/admin/`;
- автоматическая публикация одобренной заявки;
- пять серверных тестов.

## Локальная проверка

```powershell
node --test test/validation.test.js
npx wrangler@latest d1 migrations apply tmaps-community --local
npx wrangler@latest dev
```

## Секреты

Секреты никогда не записываются в Git. Перед публикацией нужно добавить:

```powershell
npx wrangler@latest secret put ADMIN_TOKEN
npx wrangler@latest secret put RATE_LIMIT_SALT
```

`TURNSTILE_SECRET` добавляется тем же способом после создания виджета
Cloudflare Turnstile. Полный порядок переноса описан в
`docs/BACKEND_MIGRATION_RU.md`.
