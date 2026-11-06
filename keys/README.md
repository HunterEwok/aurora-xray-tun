# Ключи подписи

`build.sh` подписывает пакет публичной тестовой парой ОМП для профиля Regular
(«Noname developer, for testing only»). ОМП публикует её для всех разработчиков, это
не секрет. Телефон принимает пакеты с такой подписью только в режиме разработчика.

Скрипт скачивает файлы сам и сверяет их SHA-256:

| Файл | Откуда | SHA-256 |
|---|---|---|
| `regular_key.pem` | https://developer.auroraos.ru/content-images/dev-documentation/regular_key.pem | `5d0d87728ddb719dcd506635b093efd2da303a990e0085c885d53aeb5282d6c5` |
| `regular_cert.pem` | https://developer.auroraos.ru/content-images/dev-documentation/regular_cert.pem | `2ad68fead24760f9dc2a56274c2fd77ee3426ecdc7360890af459d81b8e2af86` |

Сайт ОМП иногда не отдаёт файлы скриптам (ответ 403). Тогда скачайте оба файла в
браузере и положите в эту папку под теми же именами.

Свои ключи (например, выданные ОМП) тоже кладите сюда под именами `regular_key.pem` и
`regular_cert.pem`: если файлы уже есть, скрипт ничего не скачивает. Ключи в git не
попадают (см. `.gitignore`).
