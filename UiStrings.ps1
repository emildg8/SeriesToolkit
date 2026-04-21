#requires -Version 5.1
# Строки интерфейса Script_Rename_ALLVideo (подключается из основного .ps1).

function Get-UiLanguageSettingsPath {
    $root = Join-Path $env:LOCALAPPDATA 'Script_Rename_ALLVideo'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    Join-Path $root 'ui-language.txt'
}

function Get-UiLanguagePreference {
    $valid = @('en', 'ru', 'de', 'es', 'fr', 'zh-CN', 'ja', 'pt-BR', 'it', 'pl', 'uk', 'ko')
    $p = Get-UiLanguageSettingsPath
    if (-not (Test-Path -LiteralPath $p)) { return 'en' }
    $code = (Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue).Trim()
    if ($valid -contains $code) { return $code }
    return 'en'
}

function Save-UiLanguagePreference([string]$Code) {
    $valid = @('en', 'ru', 'de', 'es', 'fr', 'zh-CN', 'ja', 'pt-BR', 'it', 'pl', 'uk', 'ko')
    if ($valid -notcontains $Code) { return }
    $script:UiLanguage = $Code
    Set-Content -LiteralPath (Get-UiLanguageSettingsPath) -Value $Code -Encoding UTF8 -NoNewline
}

function Get-UiLanguageComboItems {
    @(
        @{ Code = 'en'; Display = 'English' }
        @{ Code = 'ru'; Display = "Русский" }
        @{ Code = 'de'; Display = 'Deutsch' }
        @{ Code = 'es'; Display = 'Español' }
        @{ Code = 'fr'; Display = 'Français' }
        @{ Code = 'zh-CN'; Display = '中文 (简体)' }
        @{ Code = 'ja'; Display = '日本語' }
        @{ Code = 'pt-BR'; Display = 'Português (Brasil)' }
        @{ Code = 'it'; Display = 'Italiano' }
        @{ Code = 'pl'; Display = 'Polski' }
        @{ Code = 'uk'; Display = 'Українська' }
        @{ Code = 'ko'; Display = '한국어' }
    )
}

function Initialize-UiStringsCatalog {
    if ($script:UiStringsCatalog) { return }
    $en = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Cancel'
        BtnYes                   = 'Yes'
        BtnNo                    = 'No'
        BtnBack                  = 'Back'
        BtnBrowse                = 'Browse…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Language'
        OutcomeTitleFmt          = 'Done - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Done. Did everything work correctly?'
        OutcomeCleanupCheckbox   = 'Remove helper files (CSV, log, cmd) in the series folder'
        EpisodeListTitle         = 'Episode list'
        EpisodeInstructions      = "Paste URL or choose .html/.htm file.`n`nSupported:`n- Kinopoisk (episodes page)`n- Wikipedia (episode list page)`n`nLeave empty to search by title on the next step."
        UrlLabel                 = 'URL or file:'
        WikiSearchTitle          = 'Search'
        WikiSearchInstructions   = "Enter the series title.`nExample: The Sopranos`n`nNext:`n- OK: search on Wikipedia`n- Back: previous step`n- Cancel: exit"
        SavedTitle               = 'Saved'
        SavedBodyFmt             = "Episode list saved.`n`nCSV file:`n{0}`n`nStarting rename..."
        DebugBundleTitle         = 'Debug bundle'
        DebugBundleOkFmt         = "Debug bundle created:`n{0}`n`nSend this ZIP to Cursor."
        DebugBundleFail          = 'Could not create the debug bundle (check series folder access and free space).'
        OpenHtmlTitle            = 'Select saved HTML'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk returned anti-bot/captcha.`nAuto-download is unavailable now.`n`nButtons:`nYes - open Kinopoisk in browser and retry`nNo - skip Kinopoisk, continue with Wikipedia`nBack - return to URL/HTML step`nCancel - exit"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "If episodes are visible in browser:`n1) Save page as .html/.htm`n2) Click Yes and select file`n`nBack - previous step"
        WikiCancelFmt            = 'Cancelled.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Error'
        TvmazePrompt             = "Could not find titles on Kinopoisk or Wikipedia.`n`nTry TVMaze search?`nBack - return to URL/search step"
        FailedTitle              = 'Failed'
        FailedText               = "Could not get episode list.`n`nOptions:`n- add episode-titles.csv manually`n- run with -Manual`n- ask Cursor to build CSV`n`nOpen series folder?`nBack - previous step"
        FailedTextExtraCaptcha   = "`nNote: Kinopoisk may still return a captcha for automated downloads.`nTry later, another network/VPN, or use a CSV (-Manual).`n"
        PhPlaceholder            = "Fetched list contains placeholders (`"Episode N`").`nRenaming stopped.`n`nProvide another URL/HTML or valid CSV."
        PhPlaceholder2           = "Titles are still placeholders after processing.`nRenaming stopped.`n`nPlease provide another source."
        RenameSeriesTitle        = 'Rename series'
        RenameManualTitle        = 'Rename series (manual)'
        ManualDryRun             = "-Manual: CSV not found.`nRequired: episode-titles.csv or titles.csv`n`nFolder:`n{0}`n`nTemplate is not created in -DryRun."
        ManualTemplateMsg        = "CSV not found.`nTemplate created:`n{0}`n`nFill: season, episode, title`nSave UTF-8 and run with -Manual."
        PlaceholderCsvWarn       = "Current episode-titles.csv contains placeholders (`"Episode N`").`nRenaming stopped.`n`n1) Run with -RefreshEpisodeList and provide URL/HTML.`n2) Put a valid episode-titles.csv manually."
        NoTitleCsv               = "No valid episode titles found in CSV.`nRenaming stopped.`n`nPlease check episode-titles.csv."
    }
    # Русский — полный набор
    $ru = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Отмена'
        BtnYes                   = 'Да'
        BtnNo                    = 'Нет'
        BtnBack                  = 'Назад'
        BtnBrowse                = 'Обзор…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Язык'
        OutcomeTitleFmt          = 'Готово - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Готово. Всё в порядке?'
        OutcomeCleanupCheckbox   = 'Очистить служебные файлы (CSV, лог, cmd) в папке сериала'
        EpisodeListTitle         = 'Список эпизодов'
        EpisodeInstructions      = "Вставьте ссылку или выберите .html/.htm.`n`nПодходит:`n- Кинопоиск (эпизоды)`n- Википедия (список эпизодов)`n`nПусто = поиск по названию на следующем шаге."
        UrlLabel                 = 'Ссылка или файл:'
        WikiSearchTitle          = 'Поиск'
        WikiSearchInstructions   = "Введите название сериала.`nПример: Клан Сопрано`n`nДалее:`n- OK: поиск в Википедии`n- Назад: к предыдущему шагу`n- Отмена: выход"
        SavedTitle               = 'Сохранено'
        SavedBodyFmt             = "Список эпизодов сохранён.`n`nФайл CSV:`n{0}`n`nЗапускаю переименование..."
        DebugBundleTitle         = 'Отладка'
        DebugBundleOkFmt         = "Архив для отладки создан:`n{0}`n`nПередайте этот ZIP в Cursor."
        DebugBundleFail          = 'Не удалось создать архив (проверьте доступ к папке сериала и свободное место).'
        OpenHtmlTitle            = 'Выберите сохранённый HTML'
        KinopoiskTitle           = 'Кинопоиск'
        KinopoiskCaptcha         = "Кинопоиск вернул антибот/капчу.`nАвтозагрузка сейчас недоступна.`n`nКнопки:`nДа - открыть Кинопоиск и повторить`nНет - пропустить Кинопоиск, искать в Википедии`nНазад - вернуться к ссылке/файлу`nОтмена - выход"
        KinopoiskHtmlTitle       = 'Кинопоиск HTML'
        KinopoiskHtmlPrompt      = "Если эпизоды видны в браузере:`n1) Сохраните страницу как .html/.htm`n2) Нажмите Да и выберите файл`n`nНазад - к предыдущему шагу"
        WikiCancelFmt            = 'Отменено.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Ошибка'
        TvmazePrompt             = "Не удалось найти названия в Кинопоиске и Википедии.`n`nПробовать поиск на TVMaze?`nНазад - вернуться к ссылке/поиску"
        FailedTitle              = 'Ошибка'
        FailedText               = "Не удалось получить список эпизодов.`n`nВарианты:`n- добавить episode-titles.csv вручную`n- запустить с -Manual`n- попросить Cursor собрать CSV`n`nОткрыть папку сериала?`nНазад - к предыдущему шагу"
        FailedTextExtraCaptcha   = "`nПримечание: Кинопоиск всё ещё возвращает капчу для автоматической загрузки.`nПопробуйте позже, другую сеть/VPN, или используйте CSV (-Manual).`n"
        PhPlaceholder            = "Получен список-заглушка (Эпизод N / Серия N).`nПереименование остановлено.`n`nУкажите другую ссылку/HTML или корректный CSV."
        PhPlaceholder2           = "После обработки названия всё ещё заглушки.`nПереименование остановлено.`n`nНужен другой источник названий."
        RenameSeriesTitle        = 'Переименование сериала'
        RenameManualTitle        = 'Переименование сериала (ручной режим)'
        ManualDryRun             = "-Manual: CSV не найден.`nНужен: episode-titles.csv или titles.csv`n`nПапка:`n{0}`n`nВ -DryRun шаблон не создаётся."
        ManualTemplateMsg        = "CSV не найден.`nСоздан шаблон:`n{0}`n`nЗаполните: season, episode, title`nСохраните UTF-8 и запустите с -Manual."
        PlaceholderCsvWarn       = "Текущий episode-titles.csv содержит заглушки (Эпизод N / Серия N).`nПереименование остановлено.`n`n1) Запустите с -RefreshEpisodeList и укажите ссылку/HTML.`n2) Положите корректный episode-titles.csv вручную."
        NoTitleCsv               = "В CSV нет валидных названий эпизодов.`nПереименование остановлено.`n`nПроверьте файл episode-titles.csv."
    }
    # Полные переводы (все ключи как в en); пустое значение в Get-UiStrings заменяется на en
    $de = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Abbrechen'
        BtnYes                   = 'Ja'
        BtnNo                    = 'Nein'
        BtnBack                  = 'Zurück'
        BtnBrowse                = 'Durchsuchen…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Sprache'
        OutcomeTitleFmt          = 'Fertig - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Fertig. Hat alles geklappt?'
        OutcomeCleanupCheckbox   = 'Hilfsdateien (CSV, Protokoll, cmd) im Serienordner entfernen'
        EpisodeListTitle         = 'Episodenliste'
        EpisodeInstructions      = "URL einfügen oder .html/.htm wählen.`n`nUnterstützt:`n- Kinopoisk (Episodenseite)`n- Wikipedia (Episodenliste)`n`nLeer lassen = Titelsuche im nächsten Schritt."
        UrlLabel                 = 'URL oder Datei:'
        WikiSearchTitle          = 'Suche'
        WikiSearchInstructions   = "Serientitel eingeben.`nBeispiel: The Sopranos`n`nWeiter:`n- OK: Wikipedia durchsuchen`n- Zurück: vorheriger Schritt`n- Abbrechen: Beenden"
        SavedTitle               = 'Gespeichert'
        SavedBodyFmt             = "Episodenliste gespeichert.`n`nCSV-Datei:`n{0}`n`nStarte Umbenennung..."
        DebugBundleTitle         = 'Debug-Paket'
        DebugBundleOkFmt         = "Debug-Paket erstellt:`n{0}`n`nSenden Sie diese ZIP-Datei an Cursor."
        DebugBundleFail          = 'Debug-Paket konnte nicht erstellt werden (Ordnerzugriff und freien Speicher prüfen).'
        OpenHtmlTitle            = 'Gespeicherte HTML-Datei auswählen'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk meldet Anti-Bot/Captcha.`nAutomatischer Download ist derzeit nicht möglich.`n`nSchaltflächen:`nJa - Kinopoisk im Browser öffnen und erneut versuchen`nNein - Kinopoisk überspringen, mit Wikipedia fortfahren`nZurück - zur URL/HTML-Datei`nAbbrechen - Beenden"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Wenn Episoden im Browser sichtbar sind:`n1) Seite als .html/.htm speichern`n2) Ja klicken und Datei auswählen`n`nZurück - vorheriger Schritt"
        WikiCancelFmt            = 'Abgebrochen.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Fehler'
        TvmazePrompt             = "Keine Titel auf Kinopoisk oder Wikipedia gefunden.`n`nTVMaze-Suche versuchen?`nZurück - zur URL/Suche"
        FailedTitle              = 'Fehler'
        FailedText               = "Episodenliste konnte nicht geladen werden.`n`nOptionen:`n- episode-titles.csv manuell hinzufügen`n- mit -Manual ausführen`n- Cursor um CSV bitten`n`nSerienordner öffnen?`nZurück - vorheriger Schritt"
        FailedTextExtraCaptcha   = "`nHinweis: Kinopoisk kann weiterhin Captchas für automatische Downloads anzeigen.`nSpäter oder über ein anderes Netzwerk/VPN versuchen, oder CSV verwenden (-Manual).`n"
        PhPlaceholder            = "Die Liste enthält Platzhalter (`"Episode N`").`nUmbenennung gestoppt.`n`nAndere URL/HTML oder gültige CSV angeben."
        PhPlaceholder2           = "Nach der Verarbeitung sind die Titel noch Platzhalter.`nUmbenennung gestoppt.`n`nBitte eine andere Quelle angeben."
        RenameSeriesTitle        = 'Serie umbenennen'
        RenameManualTitle        = 'Serie umbenennen (manuell)'
        ManualDryRun             = "-Manual: CSV nicht gefunden.`nBenötigt: episode-titles.csv oder titles.csv`n`nOrdner:`n{0}`n`nIm -DryRun wird keine Vorlage erstellt."
        ManualTemplateMsg        = "CSV nicht gefunden.`nVorlage erstellt:`n{0}`n`nAusfüllen: season, episode, title`nAls UTF-8 speichern und mit -Manual ausführen."
        PlaceholderCsvWarn       = "Die aktuelle episode-titles.csv enthält Platzhalter (`"Episode N`").`nUmbenennung gestoppt.`n`n1) Mit -RefreshEpisodeList starten und URL/HTML angeben`n2) Gültige episode-titles.csv manuell bereitstellen"
        NoTitleCsv               = "Keine gültigen Episodentitel in der CSV.`nUmbenennung gestoppt.`n`nBitte episode-titles.csv prüfen."
    }
    $es = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Cancelar'
        BtnYes                   = 'Sí'
        BtnNo                    = 'No'
        BtnBack                  = 'Atrás'
        BtnBrowse                = 'Examinar…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Idioma'
        OutcomeTitleFmt          = 'Listo - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Listo. ¿Todo salió bien?'
        OutcomeCleanupCheckbox   = 'Eliminar archivos auxiliares (CSV, registro, cmd) en la carpeta de la serie'
        EpisodeListTitle         = 'Lista de episodios'
        EpisodeInstructions      = "Pegue la URL o elija un archivo .html/.htm.`n`nCompatible:`n- Kinopoisk (página de episodios)`n- Wikipedia (lista de episodios)`n`nDejar vacío = buscar por título en el siguiente paso."
        UrlLabel                 = 'URL o archivo:'
        WikiSearchTitle          = 'Buscar'
        WikiSearchInstructions   = "Escriba el título de la serie.`nEjemplo: Los Soprano`n`nSiguiente:`n- OK: buscar en Wikipedia`n- Atrás: paso anterior`n- Cancelar: salir"
        SavedTitle               = 'Guardado'
        SavedBodyFmt             = "Lista de episodios guardada.`n`nArchivo CSV:`n{0}`n`nIniciando cambio de nombre..."
        DebugBundleTitle         = 'Depuración'
        DebugBundleOkFmt         = "Paquete de depuración creado:`n{0}`n`nEnvíe este ZIP a Cursor."
        DebugBundleFail          = 'No se pudo crear el paquete de depuración (compruebe acceso a la carpeta y espacio libre).'
        OpenHtmlTitle            = 'Seleccionar HTML guardado'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk devolvió anti-bot/captcha.`nLa descarga automática no está disponible ahora.`n`nBotones:`nSí - abrir Kinopoisk en el navegador y reintentar`nNo - omitir Kinopoisk, continuar con Wikipedia`nAtrás - volver al paso URL/HTML`nCancelar - salir"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Si los episodios se ven en el navegador:`n1) Guarde la página como .html/.htm`n2) Pulse Sí y elija el archivo`n`nAtrás - paso anterior"
        WikiCancelFmt            = 'Cancelado.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Error'
        TvmazePrompt             = "No se encontraron títulos en Kinopoisk ni Wikipedia.`n`n¿Probar búsqueda en TVMaze?`nAtrás - volver a URL/búsqueda"
        FailedTitle              = 'Error'
        FailedText               = "No se pudo obtener la lista de episodios.`n`nOpciones:`n- añadir episode-titles.csv manualmente`n- ejecutar con -Manual`n- pedir a Cursor que genere el CSV`n`n¿Abrir carpeta de la serie?`nAtrás - paso anterior"
        FailedTextExtraCaptcha   = "`nNota: Kinopoisk puede seguir mostrando captcha para descargas automáticas.`nIntente más tarde, otra red/VPN, o use CSV (-Manual).`n"
        PhPlaceholder            = "La lista obtenida contiene marcadores (`"Episode N`").`nCambio de nombre detenido.`n`nIndique otra URL/HTML o un CSV válido."
        PhPlaceholder2           = "Tras el procesamiento, los títulos siguen siendo marcadores.`nCambio de nombre detenido.`n`nIndique otra fuente."
        RenameSeriesTitle        = 'Renombrar serie'
        RenameManualTitle        = 'Renombrar serie (manual)'
        ManualDryRun             = "-Manual: no se encontró CSV.`nNecesario: episode-titles.csv o titles.csv`n`nCarpeta:`n{0}`n`nEn -DryRun no se crea plantilla."
        ManualTemplateMsg        = "No se encontró CSV.`nPlantilla creada:`n{0}`n`nRellene: season, episode, title`nGuarde en UTF-8 y ejecute con -Manual."
        PlaceholderCsvWarn       = "episode-titles.csv actual contiene marcadores (`"Episode N`").`nCambio de nombre detenido.`n`n1) Ejecute con -RefreshEpisodeList e indique URL/HTML`n2) Coloque un episode-titles.csv válido manualmente"
        NoTitleCsv               = "No hay títulos de episodios válidos en el CSV.`nCambio de nombre detenido.`n`nRevise episode-titles.csv."
    }
    $fr = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Annuler'
        BtnYes                   = 'Oui'
        BtnNo                    = 'Non'
        BtnBack                  = 'Retour'
        BtnBrowse                = 'Parcourir…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Langue'
        OutcomeTitleFmt          = 'Terminé - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Terminé. Tout s''est bien passé ?'
        OutcomeCleanupCheckbox   = 'Supprimer les fichiers utilitaires (CSV, journal, cmd) dans le dossier de la série'
        EpisodeListTitle         = 'Liste des épisodes'
        EpisodeInstructions      = "Collez l'URL ou choisissez un fichier .html/.htm.`n`nPris en charge:`n- Kinopoisk (page épisodes)`n- Wikipedia (liste d'épisodes)`n`nLaisser vide = recherche par titre à l'étape suivante."
        UrlLabel                 = 'URL ou fichier :'
        WikiSearchTitle          = 'Rechercher'
        WikiSearchInstructions   = "Saisissez le titre de la série.`nExemple : Les Soprano`n`nSuite :`n- OK : rechercher sur Wikipedia`n- Retour : étape précédente`n- Annuler : quitter"
        SavedTitle               = 'Enregistré'
        SavedBodyFmt             = "Liste d'épisodes enregistrée.`n`nFichier CSV :`n{0}`n`nDémarrage du renommage..."
        DebugBundleTitle         = 'Débogage'
        DebugBundleOkFmt         = "Archive de débogage créée :`n{0}`n`nEnvoyez ce ZIP à Cursor."
        DebugBundleFail          = 'Impossible de créer l''archive de débogage (vérifiez l''accès au dossier et l''espace libre).'
        OpenHtmlTitle            = 'Sélectionner le HTML enregistré'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk a renvoyé anti-bot/captcha.`nLe téléchargement automatique est indisponible.`n`nBoutons :`nOui - ouvrir Kinopoisk dans le navigateur et réessayer`nNon - ignorer Kinopoisk, continuer avec Wikipedia`nRetour - revenir à l'URL/fichier`nAnnuler - quitter"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Si les épisodes sont visibles dans le navigateur :`n1) Enregistrez la page en .html/.htm`n2) Cliquez Oui et sélectionnez le fichier`n`nRetour - étape précédente"
        WikiCancelFmt            = 'Annulé.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Erreur'
        TvmazePrompt             = "Aucun titre trouvé sur Kinopoisk ou Wikipedia.`n`nEssayer la recherche TVMaze ?`nRetour - revenir à l'URL/recherche"
        FailedTitle              = 'Échec'
        FailedText               = "Impossible d'obtenir la liste des épisodes.`n`nOptions :`n- ajouter episode-titles.csv manuellement`n- lancer avec -Manual`n- demander à Cursor de créer le CSV`n`nOuvrir le dossier de la série ?`nRetour - étape précédente"
        FailedTextExtraCaptcha   = "`nRemarque : Kinopoisk peut encore afficher un captcha pour les téléchargements automatiques.`nRéessayez plus tard, un autre réseau/VPN, ou utilisez un CSV (-Manual).`n"
        PhPlaceholder            = "La liste contient des marqueurs (`"Episode N`").`nRenommage arrêté.`n`nFournissez une autre URL/HTML ou un CSV valide."
        PhPlaceholder2           = "Après traitement, les titres sont encore des marqueurs.`nRenommage arrêté.`n`nFournissez une autre source."
        RenameSeriesTitle        = 'Renommer la série'
        RenameManualTitle        = 'Renommer la série (manuel)'
        ManualDryRun             = "-Manual : CSV introuvable.`nRequis : episode-titles.csv ou titles.csv`n`nDossier :`n{0}`n`nAucun modèle créé en -DryRun."
        ManualTemplateMsg        = "CSV introuvable.`nModèle créé :`n{0}`n`nRemplissez : season, episode, title`nEnregistrez en UTF-8 et lancez avec -Manual."
        PlaceholderCsvWarn       = "episode-titles.csv contient des marqueurs (`"Episode N`").`nRenommage arrêté.`n`n1) Lancez avec -RefreshEpisodeList et fournissez URL/HTML`n2) Placez un episode-titles.csv valide manuellement"
        NoTitleCsv               = "Aucun titre d'épisode valide dans le CSV.`nRenommage arrêté.`n`nVérifiez episode-titles.csv."
    }
    $zhCN = @{
        BtnOk                    = '确定'
        BtnCancel                = '取消'
        BtnYes                   = '是'
        BtnNo                    = '否'
        BtnBack                  = '返回'
        BtnBrowse                = '浏览…'
        BtnCursor                = 'Cursor…'
        LangLabel                = '语言'
        OutcomeTitleFmt          = '完成 - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = '完成。一切正常吗？'
        OutcomeCleanupCheckbox   = '删除剧集文件夹中的辅助文件（CSV、日志、cmd）'
        EpisodeListTitle         = '剧集列表'
        EpisodeInstructions      = "粘贴网址或选择 .html/.htm 文件。`n`n支持：`n- Kinopoisk（剧集页）`n- Wikipedia（剧集列表页）`n`n留空 = 下一步按标题搜索。"
        UrlLabel                 = 'URL 或文件：'
        WikiSearchTitle          = '搜索'
        WikiSearchInstructions   = "输入剧集名称。`n示例：黑道家族`n`n下一步：`n- 确定：在 Wikipedia 搜索`n- 返回：上一步`n- 取消：退出"
        SavedTitle               = '已保存'
        SavedBodyFmt             = "剧集列表已保存。`n`nCSV 文件：`n{0}`n`n开始重命名..."
        DebugBundleTitle         = '调试'
        DebugBundleOkFmt         = "已创建调试包：`n{0}`n`n请将此 ZIP 发送给 Cursor。"
        DebugBundleFail          = '无法创建调试包（请检查文件夹访问权限和磁盘空间）。'
        OpenHtmlTitle            = '选择已保存的 HTML'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk 返回反机器人/验证码。`n暂时无法自动下载。`n`n按钮：`n是 - 在浏览器中打开 Kinopoisk 并重试`n否 - 跳过 Kinopoisk，继续 Wikipedia`n返回 - 回到 URL/文件步骤`n取消 - 退出"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "若浏览器中能看到剧集：`n1) 将页面另存为 .html/.htm`n2) 点击「是」并选择文件`n`n返回 - 上一步"
        WikiCancelFmt            = '已取消。'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = '错误'
        TvmazePrompt             = "在 Kinopoisk 和 Wikipedia 上未找到标题。`n`n尝试 TVMaze 搜索？`n返回 - 回到上一步 URL/搜索"
        FailedTitle              = '失败'
        FailedText               = "无法获取剧集列表。`n`n选项：`n- 手动添加 episode-titles.csv`n- 使用 -Manual 运行`n- 请 Cursor 生成 CSV`n`n打开剧集文件夹？`n返回 - 上一步"
        FailedTextExtraCaptcha   = "`n说明：Kinopoisk 仍可能对自动下载显示验证码。`n请稍后重试、更换网络/VPN，或使用 CSV（-Manual）。`n"
        PhPlaceholder            = "获取的列表包含占位符（「第 N 集」）。`n已停止重命名。`n`n请提供其他 URL/HTML 或有效的 CSV。"
        PhPlaceholder2           = "处理后标题仍为占位符。`n已停止重命名。`n`n请提供其他来源。"
        RenameSeriesTitle        = '重命名剧集'
        RenameManualTitle        = '重命名剧集（手动）'
        ManualDryRun             = "-Manual：未找到 CSV。`n需要：episode-titles.csv 或 titles.csv`n`n文件夹：`n{0}`n`n-DryRun 模式下不创建模板。"
        ManualTemplateMsg        = "未找到 CSV。`n已创建模板：`n{0}`n`n请填写：season, episode, title`n保存为 UTF-8 并使用 -Manual 运行。"
        PlaceholderCsvWarn       = "当前 episode-titles.csv 包含占位符（「第 N 集」）。`n已停止重命名。`n`n1) 使用 -RefreshEpisodeList 运行并提供 URL/HTML`n2) 手动放入有效的 episode-titles.csv"
        NoTitleCsv               = "CSV 中没有有效的剧集标题。`n已停止重命名。`n`n请检查 episode-titles.csv。"
    }
    $ja = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'キャンセル'
        BtnYes                   = 'はい'
        BtnNo                    = 'いいえ'
        BtnBack                  = '戻る'
        BtnBrowse                = '参照…'
        BtnCursor                = 'Cursor…'
        LangLabel                = '言語'
        OutcomeTitleFmt          = '完了 - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = '完了。問題ありませんでしたか？'
        OutcomeCleanupCheckbox   = 'シリーズフォルダー内の補助ファイル（CSV、ログ、cmd）を削除'
        EpisodeListTitle         = 'エピソード一覧'
        EpisodeInstructions      = "URL を貼り付けるか、.html/.htm ファイルを選んでください。`n`n対応:`n- Kinopoisk（エピソードページ）`n- Wikipedia（エピソード一覧）`n`n空欄 = 次の手順でタイトル検索"
        UrlLabel                 = 'URL またはファイル:'
        WikiSearchTitle          = '検索'
        WikiSearchInstructions   = "作品名を入力してください。`n例: The Sopranos`n`n次の操作:`n- OK: Wikipedia で検索`n- 戻る: 前の手順`n- キャンセル: 終了"
        SavedTitle               = '保存しました'
        SavedBodyFmt             = "エピソード一覧を保存しました。`n`nCSV ファイル:`n{0}`n`n名前の変更を開始します..."
        DebugBundleTitle         = 'デバッグ'
        DebugBundleOkFmt         = "デバッグ用 ZIP を作成しました:`n{0}`n`nこの ZIP を Cursor に送ってください。"
        DebugBundleFail          = 'デバッグ用 ZIP を作成できませんでした（フォルダーへのアクセスと空き容量を確認してください）。'
        OpenHtmlTitle            = '保存した HTML を選択'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk がボット対策/キャプチャを返しました。`n自動ダウンロードは現在できません。`n`nボタン:`nはい - ブラウザで Kinopoisk を開いて再試行`nいいえ - Kinopoisk をスキップして Wikipedia へ`n戻る - URL/ファイルの手順へ`nキャンセル - 終了"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "ブラウザでエピソードが見える場合:`n1) ページを .html/.htm で保存`n2) 「はい」をクリックしてファイルを選択`n`n戻る - 前の手順"
        WikiCancelFmt            = 'キャンセルしました。'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'エラー'
        TvmazePrompt             = "Kinopoisk と Wikipedia でタイトルが見つかりませんでした。`n`nTVMaze で検索しますか？`n戻る - URL/検索の手順へ"
        FailedTitle              = '失敗'
        FailedText               = "エピソード一覧を取得できませんでした。`n`n選択肢:`n- episode-titles.csv を手動で追加`n- -Manual で実行`n- Cursor に CSV を作成するよう依頼`n`nシリーズフォルダーを開きますか？`n戻る - 前の手順"
        FailedTextExtraCaptcha   = "`n注: Kinopoisk は自動ダウンロードにキャプチャを返すことがあります。`n時間をおいて、別のネットワーク/VPN か、CSV（-Manual）を使ってください。`n"
        PhPlaceholder            = "取得したリストにプレースホルダー（`"Episode N`"）が含まれています。`n名前の変更を中止しました。`n`n別の URL/HTML または有効な CSV を指定してください。"
        PhPlaceholder2           = "処理後もタイトルがプレースホルダーのままです。`n名前の変更を中止しました。`n`n別の情報源を指定してください。"
        RenameSeriesTitle        = 'シリーズの名前を変更'
        RenameManualTitle        = 'シリーズの名前を変更（手動）'
        ManualDryRun             = "-Manual: CSV が見つかりません。`n必要: episode-titles.csv または titles.csv`n`nフォルダー:`n{0}`n`n-DryRun ではテンプレートを作成しません。"
        ManualTemplateMsg        = "CSV が見つかりません。`nテンプレートを作成しました:`n{0}`n`n入力: season, episode, title`nUTF-8 で保存し -Manual で実行してください。"
        PlaceholderCsvWarn       = "現在の episode-titles.csv にプレースホルダー（`"Episode N`"）が含まれています。`n名前の変更を中止しました。`n`n1) -RefreshEpisodeList で実行し URL/HTML を指定`n2) 有効な episode-titles.csv を手動で置く"
        NoTitleCsv               = "CSV に有効なエピソードタイトルがありません。`n名前の変更を中止しました。`n`nepisode-titles.csv を確認してください。"
    }
    $ptBR = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Cancelar'
        BtnYes                   = 'Sim'
        BtnNo                    = 'Não'
        BtnBack                  = 'Voltar'
        BtnBrowse                = 'Procurar…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Idioma'
        OutcomeTitleFmt          = 'Concluído - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Concluído. Tudo certo?'
        OutcomeCleanupCheckbox   = 'Remover arquivos auxiliares (CSV, log, cmd) na pasta da série'
        EpisodeListTitle         = 'Lista de episódios'
        EpisodeInstructions      = "Cole a URL ou escolha um arquivo .html/.htm.`n`nCompatível:`n- Kinopoisk (página de episódios)`n- Wikipedia (lista de episódios)`n`nDeixe em branco = buscar pelo título no próximo passo."
        UrlLabel                 = 'URL ou arquivo:'
        WikiSearchTitle          = 'Pesquisar'
        WikiSearchInstructions   = "Digite o título da série.`nExemplo: The Sopranos`n`nPróximo:`n- OK: pesquisar na Wikipedia`n- Voltar: passo anterior`n- Cancelar: sair"
        SavedTitle               = 'Salvo'
        SavedBodyFmt             = "Lista de episódios salva.`n`nArquivo CSV:`n{0}`n`nIniciando renomeação..."
        DebugBundleTitle         = 'Depuração'
        DebugBundleOkFmt         = "Pacote de depuração criado:`n{0}`n`nEnvie este ZIP ao Cursor."
        DebugBundleFail          = 'Não foi possível criar o pacote de depuração (verifique o acesso à pasta e o espaço livre).'
        OpenHtmlTitle            = 'Selecionar HTML salvo'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk retornou anti-bot/captcha.`nO download automático não está disponível agora.`n`nBotões:`nSim - abrir Kinopoisk no navegador e tentar de novo`nNão - pular Kinopoisk, continuar com Wikipedia`nVoltar - retornar ao passo URL/arquivo`nCancelar - sair"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Se os episódios aparecem no navegador:`n1) Salve a página como .html/.htm`n2) Clique em Sim e selecione o arquivo`n`nVoltar - passo anterior"
        WikiCancelFmt            = 'Cancelado.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Erro'
        TvmazePrompt             = "Não foi possível encontrar títulos no Kinopoisk nem na Wikipedia.`n`nTentar pesquisa no TVMaze?`nVoltar - retornar à URL/pesquisa"
        FailedTitle              = 'Falha'
        FailedText               = "Não foi possível obter a lista de episódios.`n`nOpções:`n- adicionar episode-titles.csv manualmente`n- executar com -Manual`n- pedir ao Cursor para gerar o CSV`n`nAbrir pasta da série?`nVoltar - passo anterior"
        FailedTextExtraCaptcha   = "`nObservação: o Kinopoisk ainda pode exibir captcha para downloads automáticos.`nTente mais tarde, outra rede/VPN ou use CSV (-Manual).`n"
        PhPlaceholder            = "A lista obtida contém marcadores (`"Episode N`").`nRenomeação interrompida.`n`nForneça outra URL/HTML ou CSV válido."
        PhPlaceholder2           = "Após o processamento, os títulos ainda são marcadores.`nRenomeação interrompida.`n`nForneça outra fonte."
        RenameSeriesTitle        = 'Renomear série'
        RenameManualTitle        = 'Renomear série (manual)'
        ManualDryRun             = "-Manual: CSV não encontrado.`nNecessário: episode-titles.csv ou titles.csv`n`nPasta:`n{0}`n`nEm -DryRun o modelo não é criado."
        ManualTemplateMsg        = "CSV não encontrado.`nModelo criado:`n{0}`n`nPreencha: season, episode, title`nSalve em UTF-8 e execute com -Manual."
        PlaceholderCsvWarn       = "O episode-titles.csv atual contém marcadores (`"Episode N`").`nRenomeação interrompida.`n`n1) Execute com -RefreshEpisodeList e informe URL/HTML`n2) Coloque um episode-titles.csv válido manualmente"
        NoTitleCsv               = "Não há títulos de episódio válidos no CSV.`nRenomeação interrompida.`n`nVerifique episode-titles.csv."
    }
    $it = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Annulla'
        BtnYes                   = 'Sì'
        BtnNo                    = 'No'
        BtnBack                  = 'Indietro'
        BtnBrowse                = 'Sfoglia…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Lingua'
        OutcomeTitleFmt          = 'Fatto - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Fatto. Tutto ok?'
        OutcomeCleanupCheckbox   = 'Rimuovi file di servizio (CSV, log, cmd) nella cartella della serie'
        EpisodeListTitle         = 'Elenco episodi'
        EpisodeInstructions      = "Incolla l'URL o scegli un file .html/.htm.`n`nSupportato:`n- Kinopoisk (pagina episodi)`n- Wikipedia (elenco episodi)`n`nLascia vuoto = cerca per titolo al passo successivo."
        UrlLabel                 = 'URL o file:'
        WikiSearchTitle          = 'Cerca'
        WikiSearchInstructions   = "Inserisci il titolo della serie.`nEsempio: I Soprano`n`nAvanti:`n- OK: cerca su Wikipedia`n- Indietro: passo precedente`n- Annulla: esci"
        SavedTitle               = 'Salvato'
        SavedBodyFmt             = "Elenco episodi salvato.`n`nFile CSV:`n{0}`n`nAvvio ridenominazione..."
        DebugBundleTitle         = 'Debug'
        DebugBundleOkFmt         = "Pacchetto di debug creato:`n{0}`n`nInvia questo ZIP a Cursor."
        DebugBundleFail          = 'Impossibile creare il pacchetto di debug (controlla accesso alla cartella e spazio libero).'
        OpenHtmlTitle            = 'Seleziona HTML salvato'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk ha restituito anti-bot/captcha.`nIl download automatico non è disponibile ora.`n`nPulsanti:`nSì - apri Kinopoisk nel browser e riprova`nNo - salta Kinopoisk, continua con Wikipedia`nIndietro - torna al passo URL/file`nAnnulla - esci"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Se gli episodi sono visibili nel browser:`n1) Salva la pagina come .html/.htm`n2) Clicca Sì e seleziona il file`n`nIndietro - passo precedente"
        WikiCancelFmt            = 'Annullato.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Errore'
        TvmazePrompt             = "Nessun titolo trovato su Kinopoisk o Wikipedia.`n`nProvare la ricerca TVMaze?`nIndietro - torna a URL/ricerca"
        FailedTitle              = 'Errore'
        FailedText               = "Impossibile ottenere l'elenco episodi.`n`nOpzioni:`n- aggiungi episode-titles.csv manualmente`n- esegui con -Manual`n- chiedi a Cursor di creare il CSV`n`nAprire la cartella della serie?`nIndietro - passo precedente"
        FailedTextExtraCaptcha   = "`nNota: Kinopoisk può ancora mostrare captcha per i download automatici.`nRiprova più tardi, un'altra rete/VPN o usa CSV (-Manual).`n"
        PhPlaceholder            = "L'elenco contiene segnaposto (`"Episode N`").`nRidenominazione interrotta.`n`nFornisci un altro URL/HTML o CSV valido."
        PhPlaceholder2           = "Dopo l'elaborazione i titoli sono ancora segnaposto.`nRidenominazione interrotta.`n`nFornisci un'altra fonte."
        RenameSeriesTitle        = 'Rinomina serie'
        RenameManualTitle        = 'Rinomina serie (manuale)'
        ManualDryRun             = "-Manual: CSV non trovato.`nRichiesto: episode-titles.csv o titles.csv`n`nCartella:`n{0}`n`nIn -DryRun non viene creato il modello."
        ManualTemplateMsg        = "CSV non trovato.`nModello creato:`n{0}`n`nCompila: season, episode, title`nSalva UTF-8 ed esegui con -Manual."
        PlaceholderCsvWarn       = "episode-titles.csv contiene segnaposto (`"Episode N`").`nRidenominazione interrotta.`n`n1) Esegui con -RefreshEpisodeList e fornisci URL/HTML`n2) Metti manualmente un episode-titles.csv valido"
        NoTitleCsv               = "Nessun titolo episodio valido nel CSV.`nRidenominazione interrotta.`n`nControlla episode-titles.csv."
    }
    $pl = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Anuluj'
        BtnYes                   = 'Tak'
        BtnNo                    = 'Nie'
        BtnBack                  = 'Wstecz'
        BtnBrowse                = 'Przeglądaj…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Język'
        OutcomeTitleFmt          = 'Gotowe - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Gotowe. Wszystko w porządku?'
        OutcomeCleanupCheckbox   = 'Usuń pliki pomocnicze (CSV, log, cmd) w folderze serialu'
        EpisodeListTitle         = 'Lista odcinków'
        EpisodeInstructions      = "Wklej adres URL lub wybierz plik .html/.htm.`n`nObsługiwane:`n- Kinopoisk (strona odcinków)`n- Wikipedia (lista odcinków)`n`nPuste pole = wyszukiwanie po tytule w następnym kroku."
        UrlLabel                 = 'URL lub plik:'
        WikiSearchTitle          = 'Szukaj'
        WikiSearchInstructions   = "Wpisz tytuł serialu.`nPrzykład: Rodzina Soprano`n`nDalej:`n- OK: szukaj w Wikipedii`n- Wstecz: poprzedni krok`n- Anuluj: wyjście"
        SavedTitle               = 'Zapisano'
        SavedBodyFmt             = "Lista odcinków zapisana.`n`nPlik CSV:`n{0}`n`nRozpoczynam zmianę nazw..."
        DebugBundleTitle         = 'Debug'
        DebugBundleOkFmt         = "Utworzono paczkę debug:`n{0}`n`nWyślij ten ZIP do Cursor."
        DebugBundleFail          = 'Nie można utworzyć paczki debug (sprawdź dostęp do folderu i miejsce na dysku).'
        OpenHtmlTitle            = 'Wybierz zapisany HTML'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk zwrócił ochronę antybot/captcha.`nAutomatyczne pobieranie jest teraz niedostępne.`n`nPrzyciski:`nTak - otwórz Kinopoisk w przeglądarce i spróbuj ponownie`nNie - pomiń Kinopoisk, kontynuuj z Wikipedią`nWstecz - wróć do kroku URL/plik`nAnuluj - wyjście"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Jeśli odcinki widać w przeglądarce:`n1) Zapisz stronę jako .html/.htm`n2) Kliknij Tak i wybierz plik`n`nWstecz - poprzedni krok"
        WikiCancelFmt            = 'Anulowano.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Błąd'
        TvmazePrompt             = "Nie znaleziono tytułów na Kinopoisku ani w Wikipedii.`n`nSpróbować wyszukiwania TVMaze?`nWstecz - wróć do URL/wyszukiwania"
        FailedTitle              = 'Błąd'
        FailedText               = "Nie udało się pobrać listy odcinków.`n`nOpcje:`n- dodaj episode-titles.csv ręcznie`n- uruchom z -Manual`n- poproś Cursor o CSV`n`nOtworzyć folder serialu?`nWstecz - poprzedni krok"
        FailedTextExtraCaptcha   = "`nUwaga: Kinopoisk może nadal zwracać captcha przy automatycznym pobieraniu.`nSpróbuj później, innej sieci/VPN lub użyj CSV (-Manual).`n"
        PhPlaceholder            = "Pobrana lista zawiera placeholdery (`"Episode N`").`nZmiana nazw zatrzymana.`n`nPodaj inny URL/HTML lub poprawny CSV."
        PhPlaceholder2           = "Po przetworzeniu tytuły nadal są placeholderami.`nZmiana nazw zatrzymana.`n`nPodaj inne źródło."
        RenameSeriesTitle        = 'Zmień nazwy serialu'
        RenameManualTitle        = 'Zmień nazwy serialu (ręcznie)'
        ManualDryRun             = "-Manual: CSV nie znaleziony.`nWymagany: episode-titles.csv lub titles.csv`n`nFolder:`n{0}`n`nW -DryRun szablon nie jest tworzony."
        ManualTemplateMsg        = "CSV nie znaleziono.`nUtworzono szablon:`n{0}`n`nWypełnij: season, episode, title`nZapisz UTF-8 i uruchom z -Manual."
        PlaceholderCsvWarn       = "Bieżący episode-titles.csv zawiera placeholdery (`"Episode N`").`nZmiana nazw zatrzymana.`n`n1) Uruchom z -RefreshEpisodeList i podaj URL/HTML`n2) Włóż ręcznie poprawny episode-titles.csv"
        NoTitleCsv               = "Brak poprawnych tytułów odcinków w CSV.`nZmiana nazw zatrzymana.`n`nSprawdź episode-titles.csv."
    }
    $uk = @{
        BtnOk                    = 'OK'
        BtnCancel                = 'Скасувати'
        BtnYes                   = 'Так'
        BtnNo                    = 'Ні'
        BtnBack                  = 'Назад'
        BtnBrowse                = 'Огляд…'
        BtnCursor                = 'Cursor…'
        LangLabel                = 'Мова'
        OutcomeTitleFmt          = 'Готово - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = 'Готово. Усе гаразд?'
        OutcomeCleanupCheckbox   = 'Прибрати службові файли (CSV, лог, cmd) у папці серіалу'
        EpisodeListTitle         = 'Список епізодів'
        EpisodeInstructions      = "Вставте посилання або виберіть .html/.htm.`n`nПідходить:`n- Kinopoisk (епізоди)`n- Вікіпедія (список епізодів)`n`nПорожньо = пошук за назвою на наступному кроці."
        UrlLabel                 = 'Посилання або файл:'
        WikiSearchTitle          = 'Пошук'
        WikiSearchInstructions   = "Введіть назву серіалу.`nПриклад: Клан Сопрано`n`nДалі:`n- OK: пошук у Вікіпедії`n- Назад: попередній крок`n- Скасувати: вихід"
        SavedTitle               = 'Збережено'
        SavedBodyFmt             = "Список епізодів збережено.`n`nФайл CSV:`n{0}`n`nЗапускаю перейменування..."
        DebugBundleTitle         = 'Налагодження'
        DebugBundleOkFmt         = "Архів для налагодження створено:`n{0}`n`nНадішліть цей ZIP у Cursor."
        DebugBundleFail          = 'Не вдалося створити архів (перевірте доступ до папки та вільне місце).'
        OpenHtmlTitle            = 'Виберіть збережений HTML'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk повернув антибот/капчу.`nАвтозавантаження зараз недоступне.`n`nКнопки:`nТак - відкрити Kinopoisk у браузері й повторити`nНі - пропустити Kinopoisk, шукати у Вікіпедії`nНазад - повернутися до посилання/файлу`nСкасувати - вихід"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "Якщо епізоди видно в браузері:`n1) Збережіть сторінку як .html/.htm`n2) Натисніть Так і виберіть файл`n`nНазад - до попереднього кроку"
        WikiCancelFmt            = 'Скасовано.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = 'Помилка'
        TvmazePrompt             = "Не вдалося знайти назви в Kinopoisk і Вікіпедії.`n`nСпробувати пошук на TVMaze?`nНазад - повернутися до посилання/пошуку"
        FailedTitle              = 'Помилка'
        FailedText               = "Не вдалося отримати список епізодів.`n`nВаріанти:`n- додати episode-titles.csv вручну`n- запустити з -Manual`n- попросити Cursor зібрати CSV`n`nВідкрити папку серіалу?`nНазад - попередній крок"
        FailedTextExtraCaptcha   = "`nПримітка: Kinopoisk може й далі повертати капчу для автоматичного завантаження.`nСпробуйте пізніше, іншу мережу/VPN або використайте CSV (-Manual).`n"
        PhPlaceholder            = "Отримано список-заглушка (Епізод N / Серія N).`nПерейменування зупинено.`n`nВкажіть інше посилання/HTML або коректний CSV."
        PhPlaceholder2           = "Після обробки назви все ще заглушки.`nПерейменування зупинено.`n`nПотрібне інше джерело назв."
        RenameSeriesTitle        = 'Перейменування серіалу'
        RenameManualTitle        = 'Перейменування серіалу (ручний режим)'
        ManualDryRun             = "-Manual: CSV не знайдено.`nПотрібен: episode-titles.csv або titles.csv`n`nПапка:`n{0}`n`nУ -DryRun шаблон не створюється."
        ManualTemplateMsg        = "CSV не знайдено.`nСтворено шаблон:`n{0}`n`nЗаповніть: season, episode, title`nЗбережіть UTF-8 і запустіть з -Manual."
        PlaceholderCsvWarn       = "Поточний episode-titles.csv містить заглушки (Епізод N / Серія N).`nПерейменування зупинено.`n`n1) Запустіть з -RefreshEpisodeList і вкажіть посилання/HTML`n2) Покладіть коректний episode-titles.csv вручну"
        NoTitleCsv               = "У CSV немає дійсних назв епізодів.`nПерейменування зупинено.`n`nПеревірте episode-titles.csv."
    }
    $ko = @{
        BtnOk                    = 'OK'
        BtnCancel                = '취소'
        BtnYes                   = '예'
        BtnNo                    = '아니오'
        BtnBack                  = '뒤로'
        BtnBrowse                = '찾아보기…'
        BtnCursor                = 'Cursor…'
        LangLabel                = '언어'
        OutcomeTitleFmt          = '완료 - Script_Rename_ALLVideo {0}'
        OutcomeDoneQuestion      = '완료. 문제없이 끝났나요?'
        OutcomeCleanupCheckbox   = '시리즈 폴더에서 보조 파일(CSV, 로그, cmd) 삭제'
        EpisodeListTitle         = '에피소드 목록'
        EpisodeInstructions      = "URL을 붙여넣거나 .html/.htm 파일을 선택하세요.`n`n지원:`n- Kinopoisk(에피소드 페이지)`n- Wikipedia(에피소드 목록)`n`n비워 두면 다음 단계에서 제목으로 검색합니다."
        UrlLabel                 = 'URL 또는 파일:'
        WikiSearchTitle          = '검색'
        WikiSearchInstructions   = "시리즈 제목을 입력하세요.`n예: The Sopranos`n`n다음:`n- OK: Wikipedia에서 검색`n- 뒤로: 이전 단계`n- 취소: 종료"
        SavedTitle               = '저장됨'
        SavedBodyFmt             = "에피소드 목록을 저장했습니다.`n`nCSV 파일:`n{0}`n`n이름 바꾸기 시작..."
        DebugBundleTitle         = '디버그'
        DebugBundleOkFmt         = "디버그 번들이 생성되었습니다:`n{0}`n`n이 ZIP을 Cursor로 보내세요."
        DebugBundleFail          = '디버그 번들을 만들 수 없습니다(폴더 접근과 여유 공간을 확인하세요).'
        OpenHtmlTitle            = '저장한 HTML 선택'
        KinopoiskTitle           = 'Kinopoisk'
        KinopoiskCaptcha         = "Kinopoisk이 봇 방지/캡차를 반환했습니다.`n자동 다운로드를 사용할 수 없습니다.`n`n버튼:`n예 - 브라우저에서 Kinopoisk 열고 다시 시도`n아니오 - Kinopoisk 건너뛰고 Wikipedia 계속`n뒤로 - URL/파일 단계로`n취소 - 종료"
        KinopoiskHtmlTitle       = 'Kinopoisk HTML'
        KinopoiskHtmlPrompt      = "브라우저에서 에피소드를 볼 수 있으면:`n1) 페이지를 .html/.htm으로 저장`n2) 예를 누르고 파일 선택`n`n뒤로 - 이전 단계"
        WikiCancelFmt            = '취소되었습니다.'
        ToolNameFmt              = 'Script_Rename_ALLVideo {0}'
        ErrorTitle               = '오류'
        TvmazePrompt             = "Kinopoisk와 Wikipedia에서 제목을 찾지 못했습니다.`n`nTVMaze 검색을 시도할까요?`n뒤로 - URL/검색 단계로"
        FailedTitle              = '실패'
        FailedText               = "에피소드 목록을 가져올 수 없습니다.`n`n옵션:`n- episode-titles.csv를 수동으로 추가`n- -Manual로 실행`n- Cursor에 CSV 생성 요청`n`n시리즈 폴더를 열까요?`n뒤로 - 이전 단계"
        FailedTextExtraCaptcha   = "`n참고: Kinopoisk은 자동 다운로드에 캡차를 반환할 수 있습니다.`n나중에 다시 시도하거나 다른 네트워크/VPN을 사용하거나 CSV(-Manual)를 사용하세요.`n"
        PhPlaceholder            = "가져온 목록에 자리 표시자(`"Episode N`")가 있습니다.`n이름 바꾸기를 중단했습니다.`n`n다른 URL/HTML 또는 유효한 CSV를 제공하세요."
        PhPlaceholder2           = "처리 후에도 제목이 자리 표시자입니다.`n이름 바꾸기를 중단했습니다.`n`n다른 출처를 제공하세요."
        RenameSeriesTitle        = '시리즈 이름 바꾸기'
        RenameManualTitle        = '시리즈 이름 바꾸기(수동)'
        ManualDryRun             = "-Manual: CSV를 찾을 수 없습니다.`n필요: episode-titles.csv 또는 titles.csv`n`n폴더:`n{0}`n`n-DryRun에서는 템플릿을 만들지 않습니다."
        ManualTemplateMsg        = "CSV를 찾을 수 없습니다.`n템플릿을 만들었습니다:`n{0}`n`n입력: season, episode, title`nUTF-8로 저장하고 -Manual로 실행하세요."
        PlaceholderCsvWarn       = "현재 episode-titles.csv에 자리 표시자(`"Episode N`")가 있습니다.`n이름 바꾸기를 중단했습니다.`n`n1) -RefreshEpisodeList로 실행하고 URL/HTML 제공`n2) 유효한 episode-titles.csv를 수동으로 넣기"
        NoTitleCsv               = "CSV에 유효한 에피소드 제목이 없습니다.`n이름 바꾸기를 중단했습니다.`n`nepisode-titles.csv를 확인하세요."
    }
    $script:UiStringsCatalog = @{
        en    = $en
        ru    = $ru
        de    = $de
        es    = $es
        fr    = $fr
        'zh-CN' = $zhCN
        ja    = $ja
        'pt-BR' = $ptBR
        it    = $it
        pl    = $pl
        uk    = $uk
        ko    = $ko
    }
}

function Get-UiStrings {
    Initialize-UiStringsCatalog
    $lang = $script:UiLanguage
    if (-not $script:UiStringsCatalog.ContainsKey($lang)) { $lang = 'en' }
    $base = $script:UiStringsCatalog['en']
    $cur = $script:UiStringsCatalog[$lang]
    $out = @{}
    foreach ($k in $base.Keys) {
        $v = $cur[$k]
        if ([string]::IsNullOrWhiteSpace($v)) { $v = $base[$k] }
        $out[$k] = $v
    }
    return $out
}
