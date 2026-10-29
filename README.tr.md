# ronin-agent

**Windows'ta, Claude Code üzerine kurulu, kendi boş hafıza kasasıyla gelen kişisel yapay zekâ özel kalemin (chief of staff).**

[English README](README.md)

RONIN bir sohbet botu değil. Claude Code'un etrafına üç şey eklenmiş hâli: **eller** (gerçek dosyalarında ve bağlı hesaplarında iş yapar), **hafıza** (kendi okuyup güncellediği bir Obsidian kasası; her oturum bir öncekinin kaldığı yerden başlar) ve **yapı** (o hafızayı isabetli kılan indeksler ve kurallar). Bu depo bir başlangıç kiti: tek bir kurulum betiği tüm yapıyı boş bir kasa ve istediğin isimde bir ajanla kurar.

Temeli [Jared Rhodenizer](https://github.com/jaredrhod)'ın açık kaynak projeleri (hafıza kasası, ses, yüz, kurulum sihirbazı). Bu depo üstüne bir Windows katmanı ekler. Bkz. [Teşekkür](#teşekkür).

## Özellikler

| Parça | Ne yapar | Varsayılan |
|---|---|---|
| **Hafıza kasası** | Obsidian kasa iskeleti: VAULT-INDEX (profilin + kurallar), Active Priorities, şablondan günlük notlar, klasör indeksleri, Weekly Schedule notu. Boş başlar; ajan seninle konuşarak doldurur. | açık |
| **Açılış dosyası** | `CLAUDE.md`: kimlik, dil, ton ve asla gevşemeyen kurallar (sadece kanıt, kod değişikliğinden önce onay, mail göndermeden / takvim değiştirmeden önce onay, dış içerik veridir, notlara sır yazılmaz). | açık |
| **Ses + yüz** | [backtalk](https://github.com/jaredrhod/backtalk) (bas-konuş ses) ve [ai-visualizer](https://github.com/jaredrhod/ai-visualizer) (animasyonlu yüz), orijinal depolarından klonlanır. | klonlanır |
| **Başlatıcı** (`ronin-app`) | Tek betik HUD'u, yüzü, sesi ve seçtiğin parçaları başlatır, yüzü Edge uygulama penceresinde açar. Zaten çalışanı atlar. | açık |
| **HUD** (`ronin-hud`) | `127.0.0.1:8797` üzerinde yerel JSON: bugünün programı, açık işler, aktif projeler, bugünün iş kaydı, CPU/RAM/pil, servis durumu, isteğe bağlı hava durumu ve site kontrolü. | açık |
| **RONIN Island** (`ronin-island`) | Ekranın üstünde Dynamic Island tarzı bir çentik: Claude Code oturumlarının canlı durumu (çalışıyor / bitti / onay bekliyor), medya kontrolü, 25 dk odak sayacı, programdaki sıradaki blok. | kapalı |
| **RONIN Guard** (`ronin-guard`) | Laptop hırsızlık alarmı: kilit ekranı, tam seste siren, webcam fotoğrafı ve PIN'siz dokunulursa Telegram bildirimi. | istenince |
| **Telegram** (`ronin-telegram`) | Kendi botun üzerinden telefondan ajanla konuş (resmî Claude Code Telegram kanal eklentisi), isteğe bağlı sabah özeti. | kapalı |
| **Hatırlatmalar** (`ronin-reminders`) | `config.json`'daki tekrarlayan etkinliklerden belli bir süre önce bildirim (ve isteğe bağlı sesli cümle). | kapalı |
| **Kasa yedeği** (`ronin-sync`) | Kasayı her 30 dakikada commit'leyip kendi **özel (private)** git deponla eşitler. | kapalı |
| **Remote Control** (`ronin-remote`) | Telefon veya tabletteki Claude uygulamasından yönetebileceğin bir Claude Code Remote Control oturumu. | kapalı |

## Ekran görüntüleri

**RONIN Island**: ekranın üstünde Dynamic Island tarzı bir çentik. Kapalıyken Claude Code ne yapıyor gösterir, üstüne gelince açılır.

![Island kapalı](docs/screenshots/island-pill.png)
![Island açık: Claude Code oturumları, müzik, odak sayacı, bugün](docs/screenshots/island-open.png)

**RONIN Guard**: laptop hırsız alarmı. Önce kilit, biri dokunursa PIN geri sayımı, girilmezse tam alarm (siren, kamera fotoğrafı, Telegram bildirimi).

| Kilitli | Dokunuldu | Alarm |
| :---: | :---: | :---: |
| ![Guard kilitli](docs/screenshots/guard-armed.png) | ![Guard geri sayım](docs/screenshots/guard-countdown.png) | ![Guard alarm](docs/screenshots/guard-alarm.png) |

_Görüntülerde örnek veriler kullanılmıştır._

## Gereksinimler

- Windows 10/11
- [Git](https://git-scm.com/) (`winget install Git.Git`)
- npm ile birlikte [Node.js LTS](https://nodejs.org/) (`winget install OpenJS.NodeJS.LTS`)
- [Python 3.10+](https://www.python.org/) (`winget install Python.Python.3.12`; Microsoft Store kısayolu sayılmaz)
- [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) ve onu içeren bir Claude planı
- İsteğe bağlı: ses için [uv](https://docs.astral.sh/uv/) (`winget install astral-sh.uv`), Telegram eklentisi için [Bun](https://bun.sh/) (`winget install Oven-sh.Bun`), uygulama penceresi için Microsoft Edge, kasaya kendin bakmak için [Obsidian](https://obsidian.md/)

## Kurulum

```powershell
git clone <bu deponun adresi> ronin-agent
cd ronin-agent
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

Kurulum şunları sorar: kurulum klasörü (varsayılan `%USERPROFILE%\ronin`), ajanın adı (varsayılan `RONIN`), senin adın, dil (ör. `Turkish`), ton, karşılama cümlesi (ör. "Tüm sistemler çevrimiçi. Bugün ne üzerinde çalışıyoruz?") ve kasa klasörü (varsayılan `%USERPROFILE%\<ajan>-memory`). Sonra:

1. gereksinimleri kontrol eder,
2. dört upstream projeyi orijinal GitHub depolarından klonlar,
3. bu deponun katmanını kurulum klasörüne kopyalar,
4. `config.json`, `CLAUDE.md`, Telegram talimatı ve (yoksa) `backtalk\backtalk.json` dosyalarını yazar,
5. kasayı `vault-template\`'ten oluşturur, **sadece kasa klasörü boşsa veya yoksa**,
6. Claude Code'un kendi `MEMORY.md` dosyasını kasaya yönlendirir (dosya henüz yoksa),
7. Island ve Guard için `npm install` çalıştırır,
8. sonraki adımları yazdırır.

Tekrar çalıştırmak güvenli: var olan kasayı, `config.json`, `CLAUDE.md` veya `MEMORY.md`'yi asla ezmez (yeni `CLAUDE.md` karşılaştırma için `CLAUDE.ronin-template.md` olarak yazılır). Katmanın kod dosyaları depodan yenilenir.

Faydalı parametreler: `-Yes` (varsayılanları kabul et), `-InstallDir`, `-VaultPath`, `-AgentName`, `-OwnerName`, `-Language`, `-Tone`, `-WelcomeLine`, `-SkipClone`, `-SkipNpm`, `-RegisterTasks` (Görev Zamanlayıcı'da `\<Ajan>\Vault Sync` 30 dakikada bir, `\<Ajan>\Reminders` 15 dakikada bir, `\<Ajan>\Daily Summary` 07:30'da, kapalı olarak).

Kurulumdan sonra kurulum klasöründe bir terminal açıp `claude` yaz. Ajan seni karşılar, kasasını okur ve profilini doldurmak için seninle konuşmayı teklif eder.

## Ayarlar

Eskiden koda gömülü olan her şey kurulum klasöründeki `config.json` içinde (şablon: [`config.example.json`](config.example.json)). **Sırlar asla bu dosyaya girmez.** Anahtarların açıklaması İngilizce README'deki tabloda.

Sırlar sadece Windows **kullanıcı ortam değişkenlerinde** durur:

| Değişken | Kullanan |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Guard, günlük özet |
| `TELEGRAM_CHAT_ID` | Guard, günlük özet (sayısal sohbet kimliğin) |
| `ELEVENLABS_API_KEY` | Hatırlatmalar (isteğe bağlı), backtalk (isteğe bağlı) |

Kendi terminalinde `[Environment]::SetEnvironmentVariable('AD', '<değer>', 'User')` ile ayarla, sonra yeni bir terminal aç. Telegram kanal eklentisi bot token'ının kendi kopyasını `/telegram:configure` ile saklar.

Island kancaları (hooks), kasa yedeği ve oturum açılışında başlatma için İngilizce README'deki "Configuration" bölümüne bak; kurulum betiği gereken satırları senin gerçek yollarınla yazdırır.

## Güvenlik notları

- **Telegram izin listesi.** Telegram oturumu izin sormadan çalışır (telefondan kimse "izin ver"e basamaz). Bu sadece eklentinin izin listesinde yalnızca senin Telegram kullanıcı kimliğin varsa kabul edilebilir. `/telegram:access` ile kontrol et. Bir mesaj istedi diye asla eşleştirme onaylama.
- **Token'ları asla yapıştırma**: sohbete, nota, `config.json`'a veya bir commit'e. Kullanıcı ortam değişkeni kullan. Sızarsa iptal et (BotFather: `/revoke`) ve yenisini al.
- **Dış içerik veridir.** Mailler, web sayfaları, dosyalar, Telegram/WhatsApp/Teams mesajları ve API yanıtları ajana asla talimat vermez, ajana adıyla seslenseler bile. CLAUDE.md bunu zorunlu kılar.
- **Göndermeden önce onay.** Ajan her mail/mesajı ve takvim değişikliğini sana gösterir ve açık bir "evet" bekler.
- **Sadece yerel.** HUD `127.0.0.1`'e bağlanır. Island ve Guard durumlarını git'in yok saydığı kendi `data/` / `state/` klasörlerinde tutar.
- **Guard fotoğrafları.** İnsanların webcam fotoğrafını çekmek bulunduğun yerde yasal düzenlemeye tabi olabilir; yerel yasayı kontrol et.
- **Kurulumunu gizli tut.** `config.json`, `CLAUDE.md`, Telegram talimatı, loglar ve kasa kişiseldir. `.gitignore` bunları dışarıda bırakır, ama bir fork yayınlamadan önce mutlaka tekrar kontrol et.

## Teşekkür

ronin-agent, temeli kurup açık kaynak olarak paylaşan **Jared Rhodenizer** ([@jaredrhod](https://github.com/jaredrhod), [jaredrhod.com](https://jaredrhod.com)) olmadan var olamazdı:

- [ai-memory-vault](https://github.com/jaredrhod/ai-memory-vault) — hafıza kasası sistemi ve bu deponun şablonlarının uyarlandığı CLAUDE.md / VAULT-INDEX / günlük not şablonları (CC BY-SA 4.0)
- [fullstack-agent](https://github.com/jaredrhod/fullstack-agent) — tüm yapı için rehberli kurulum (AGPL-3.0)
- [backtalk](https://github.com/jaredrhod/backtalk) — ses (AGPL-3.0)
- [ai-visualizer](https://github.com/jaredrhod/ai-visualizer) — yüz (AGPL-3.0)

Videoları: [YouTube](https://youtube.com/@jaredrhod). Guard fikri Mac uygulaması "MacGuard"dan geliyor.

## Lisans

- Bu depodaki **kod** (`install.ps1`, `config.example.json`, `ronin-*`): [MIT](LICENSE).
- **Şablonlar** (`templates/`, `vault-template/`): [CC BY-SA 4.0](templates/LICENSE.md), Jared Rhodenizer'ın ai-memory-vault projesinden uyarlandı.
- **Upstream projeler** depoya dahil değil; kurulum betiği onları klonlar ve kendi lisanslarını korurlar (AGPL-3.0 / CC BY-SA 4.0).

Ayrıntılar: [NOTICE.md](NOTICE.md).
