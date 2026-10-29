# Claude Code — جدولة المهام على تجديد الحصة

سكربت PowerShell يشتغل في الخلفية، وينفّذ مهمة (من `task.md`) في **سيشن Claude Code جديدة** كل مرة تتجدد فيها حصة الـ 5 ساعات — للأبد لحد ما توقفه بنفسك.

## إزاي بيعرف وقت التجديد؟
السكربت بيشغّل المهمة بصيغة `stream-json`، وكلود بيرجّع ضمن المخرجات حدث اسمه
`rate_limit_event` بيحتوي **وقت تجديد نافذة الـ 5 ساعات بالظبط** (`resetsAt`) لنوع
`five_hour`. فالسكربت:
1. ينفّذ المهمة.
2. يقرأ `resetsAt` الحقيقي من مخرجات كلود.
3. ينام لحد وقت التجديد + دقيقتين (buffer).
4. ينفّذ تاني… وهكذا.

ده أدق من مجرد "5 ساعات من وقت التشغيل"، لأنه بيمسك حدود النافذة الفعلية حتى لو
كنت استخدمت كلود يدوياً قبل كده. ولو مالقاش الحدث لأي سبب، بيرجع تلقائياً للطريقة
البديلة: 5 ساعات من لحظة التشغيل (self-anchor).

## الملفات
| الملف | الوظيفة |
|------|---------|
| `task.md` | **هنا تكتب المهمة.** عدّلها في أي وقت؛ بتتقري قبل كل تشغيل. |
| `config.json` | الإعدادات (المسارات، مدة النافذة، الموديل، صلاحيات…). |
| `run-watcher.ps1` | حلقة الـ watcher نفسها. |
| `start-watcher.ps1` | يشغّله في الخلفية (نافذة مخفية). |
| `stop-watcher.ps1` | يوقفه بلطف. |
| `status-watcher.ps1` | يعرض الحالة وآخر السجل. |
| `logs/` | سجلات يومية + سجل لكل تشغيل. |

## التشغيل
1. اكتب مهمتك في `task.md`.
2. راجع `config.json` (خصوصاً `projectDir`).
3. شغّل مرة واحدة:
   ```powershell
   cd f:\AI\auto-code\claude-scheduler
   powershell -ExecutionPolicy Bypass -File .\start-watcher.ps1
   ```
4. للمتابعة:  `powershell -ExecutionPolicy Bypass -File .\status-watcher.ps1`
5. للإيقاف:  `powershell -ExecutionPolicy Bypass -File .\stop-watcher.ps1`

> لو عايزه يشتغل في الطرفية الحالية وتشوف السجل مباشرة (بدل الخلفية):
> `powershell -ExecutionPolicy Bypass -File .\run-watcher.ps1`

## إعدادات `config.json`
| المفتاح | الشرح |
|--------|-------|
| `claudePath` | مسار `claude.exe`. سيبه `""` علشان يلاقيه تلقائياً من إضافة VSCode. |
| `projectDir` | مجلد المشروع اللي كلود هيشتغل فيه. |
| `taskFile` | ملف المهمة (نسبي للمجلد ده أو مسار كامل). |
| `windowHours` | مدة نافذة الحصة (افتراضي 5). |
| `bufferMinutes` | دقائق إضافية بعد التجديد ضماناً (افتراضي 2). |
| `model` | الموديل (مثلاً `opus` أو `sonnet`). فاضي = الافتراضي. |
| `permissionMode` | وضع الصلاحيات (`bypassPermissions` للتشغيل بدون تدخّل). |
| `extraArgs` | فلاجز إضافية. الافتراضي `--dangerously-skip-permissions` للتشغيل الكامل بلا أسئلة. |
| `runAtStart` | `true` = نفّذ فوراً عند التشغيل. `false` = استنّى نافذة كاملة الأول. |
| `heartbeatMinutes` | كل كام دقيقة يكتب سطر "في الانتظار" في السجل. |
| `emptyTaskRecheckMinutes` | لو `task.md` فاضي، يعيد الفحص بعد كام دقيقة. |
| `mode` | `window` = عند تجديد الحصة (افتراضي). `datetime` = وقت وتاريخ محدد. |
| `schedule.runAt` | (لوضع datetime) التاريخ والوقت بصيغة `YYYY-MM-DDTHH:mm` مثلاً `2026-07-20T09:00`. |
| `schedule.repeat` | `none` (مرة واحدة) / `hourly` / `daily` / `weekly` / `everyNHours`. |
| `schedule.everyNHours` | عدد الساعات لو `repeat = everyNHours`. |

### وضع الوقت/التاريخ (datetime)
عيّن `mode: "datetime"` واملأ `schedule`. أمثلة:
- **مرة واحدة الساعة 9 صباح 20 يوليو:** `runAt: "2026-07-20T09:00"`، `repeat: "none"`.
- **يومياً 9 صباحاً:** `runAt: "2026-07-20T09:00"`، `repeat: "daily"`.
- **كل 3 ساعات:** `runAt: "2026-07-20T09:00"`، `repeat: "everyNHours"`، `everyNHours: 3`.

> أسهل طريقة لضبط ده: من **أيقونة الجدولة في إضافة Claude Companion** (منتقي تاريخ/وقت جاهز).

## ⚠️ ملاحظة أمان مهمة
الإعداد الافتراضي بيستخدم `--dangerously-skip-permissions` عشان كلود ينفّذ من غير ما يستناك توافق على كل خطوة (ضروري للتشغيل غير المراقب). ده معناه إن كلود هيقدر يعدّل ملفات ويشغّل أوامر بحرية في `projectDir`. تأكد إن المهمة والمجلد اللي شغّاله فيهم موثوقين. لو عايز أمان أعلى، غيّر `permissionMode` لـ `acceptEdits` وشيل `extraArgs` — بس ساعتها ممكن يقف مستنّي موافقة على بعض الأدوات.

## التشغيل التلقائي عند بدء الويندوز
عشان الـ watcher يشتغل لوحده عند كل تسجيل دخول (بيكمل حتى بعد إعادة التشغيل)، بدون صلاحيات أدمن:
```powershell
powershell -ExecutionPolicy Bypass -File .\install-startup-task.ps1
```
ده بيحط مشغّل مخفي في مجلد Startup بتاعك:
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ClaudeSchedulerWatcher.vbs`
- بيشتغل مخفي تماماً (بدون أي نافذة).
- **بيبدأ من تسجيل الدخول الجاي.** لو عايزه يشتغل دلوقتي كمان: `.\start-watcher.ps1`.
- لإلغاء التشغيل التلقائي: `.\uninstall-startup-task.ps1`.

> لو بتفضّل Windows Task Scheduler بدل ده، سجّل مهمة عند "At log on" تشغّل
> `start-watcher.ps1` — بس ده محتاج PowerShell بصلاحيات أدمن.

## قيود
- كل تشغيل = سيشن مستقلة (مش بتكمّل السيشن اللي قبلها). لو عايزها تكمّل، ممكن نضيف `--continue`.
