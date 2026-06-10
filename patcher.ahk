#Requires AutoHotkey v2.0
#SingleInstance Force
#include "lib\ImagePut.ahk"

global ProcessedFiles := []
global IsPatchingNow := false
global line := 0
global CustomFileList := false


CoordMode("Mouse", "Client")

TraySetIcon("shell32.dll","133")
MyGui := Gui("", "L2 File Patcher")
MyGui.SetFont("s10", "Segoe UI")


global FileListView := MyGui.Add("ListView", "x177 y10 w400 h200", ["Файл", "Статус"])
FileListView.ModifyCol(1, 135)
FileListView.ModifyCol(2, 235)

global SB := MyGui.Add("StatusBar",, "")

gif := []
gif.hwnd := ImageShow("resources\picture.gif",, [5, 15], 0x40000000 | 0x10000000 | 0x8000000 | 0x20,, MyGui.hwnd, False)

CheckResources()

; Поддерживаем перенос файлов drag&drop-ом (если скрипт запущен не из папки с конкретным патчем)
MyGui.OnEvent("DropFiles", OnFilesDropped)
; Обрабатываем клик мышкой по пауку на картинке как нажатие "Старт"
OnMessage(0x0201, WM_LBUTTONDOWN)

myGui.OnEvent('Close', (*) => ExitApp())

MyGui.Show("w600 h250")



Initizalize()
global isReady := true


;------------------------------------------------------------------------------------------------------

Initizalize(*) {
    global FilesToMod, CustomFileList

    FileListView.Delete()

    FilesToMod := ReadFilesToMod()

    ; Если скрипт запущен не из папки с патчами, то ждем ручного наполнения списка файлов
    if (FilesToMod.Length = 0) {
        SB.SetText("Перетащите файлы, которые надо пропатчить, в столбец `"Файл`"")
        CustomFileList := true
    }
    ; Если нашли папку files/system, то отображаем список файлов
    else {
        for filePath in FilesToMod {
            SplitPath(filePath, &fileName)
            FileListView.Add(, fileName, "")
            SB.SetText("Поймайте муху, чтобы начать модификацию")
        }
    }
}

;------------------------------------------------------------------------------------------------------

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    if (hwnd == MyGui.hwnd && IsReady && FilesToMod.Length != 0) {

        ; Извлекаем координаты клика относительно окна, в которое кликнули
        xPos := lParam & 0xFFFF
        yPos := lParam >> 16

        if (xPos >= 146 && xPos <= 158 && yPos >= 20 && yPos <= 39) {
            StartPatching()
        }
    }
}

; Перенос файлов только в список, только до Запуска модификации (потом нужно перезапускать скрипт) и только не из папки конкретного патча
OnFilesDropped(GuiObj, GuiCtrl, FileArray, X, Y) {
    global FilesToMod

    if (GuiCtrl != FileListView) {
        return
    }
    if !isReady || !CustomFileList
        return

    ; Работаем с полным путем к файлу, но отображать будем только имя (также как и для случая запуска из папки конкретного патча)(не предполагаем сценарий с необходимостью модифицировать одни и те же файлы, но по разным путям
    for filePath in FileArray {
        FilesToMod.Push(filePath)

        SplitPath(filePath, &fileName)
        FileListView.Add(, fileName, "")
    }

    if (FilesToMod.Length > 0) {
        SB.SetText("Добавлено файлов: " . FilesToMod.Length . ". Поймайте муху, чтобы начать модификацию")
    }
}

;------------------------------------------------------------------------------------------------------

; Проверяем, есть ли файлы diff-ы
CheckResources() {
    files := []

    if !DirExist("resources") {
        MsgBox("Нет исходников с diff-ами. Папка resources не найдена.", "Ошибка", 16)
        ExitApp
    }

    Loop Files, "resources\changes_*.txt" {
        fileName := StrReplace(A_LoopFileName, "changes_", "")
        files.Push(fileName)
    }

    if (files.Length = 0) {
        MsgBox("Нет исходников с diff-ами. Папка resources пуста.", "Ошибка", 16)
        ExitApp
    }

    return files
}

; Заполняем список файлов для модификации, получаем полный путь, но в списке потом отобразим только имя
ReadFilesToMod() {
    files := []

    if !DirExist(A_ScriptDir . "\..\files\System") {
        return files
    }

    Loop Files, A_ScriptDir . "\..\files\System\*.txt" {
        files.Push(A_LoopFileFullPath)
    }

    return files
}

;------------------------------------------------------------------------------------------------------

; Делаем бекап перед каждой модификацией, запуски группируем по дате.
CreateBackupDirectory() {
    currentDate := FormatTime(, "yyyy_MM_dd")
    baseDir := "backup\" . currentDate
    counter := 1
    backupDir := baseDir

    while DirExist(backupDir) {
        isEmpty := true
        Loop Files, backupDir . "\*.*" {
            isEmpty := false
            break
        }

        if isEmpty {
            break
        }

        counter++
        backupDir := baseDir . "_" . counter
    }

    if !DirExist(backupDir) {
        DirCreate(backupDir)
    }
    return backupDir
}

; Очистка временной папки
CleanTempDirectory() {
    if DirExist("temp") {
        Loop Files, "temp\*.*" {
            try {
                FileDelete(A_LoopFileFullPath)
            }
        }
    } else {
        DirCreate("temp")
    }
}

;------------------------------------------------------------------------------------------------------

StartPatching(*) {
    global isReady, ProcessedFiles, FilesToMod, line, CustomFileList

    ; Если скрипт запустили из директории патча
    if !CustomFileList {
        result := MsgBox("Внимание. Модифицировать можно только свежие оригинальные файлы игры. Вы точно сделали Full-check?", "Подтверждение", "YesNo Icon! 4096")
        if (result = "No") {
            return
        }
    }

    ; Дальше в коде isReady нигде не присваиваем true. Чтобы модифицировать другие файлы, Программу нужно будет закрыть и запустить заново
    isReady := false

    line := 0
    ProcessedFiles := []

    try {

        backupDir := CreateBackupDirectory()
        CleanTempDirectory()
        Play("ahk_id " gif.hwnd)

        for filePath in FilesToMod {
            ProcessFile(filePath, backupDir)
        }

        ; Анимацию останавливаем и принудительно переводим в последний кадр
        Stop("ahk_id " gif.hwnd)
        Step("ahk_id " gif.hwnd, 9)
        ;CleanTempDirectory()

        ; Если в бекапе по итогу ничего нет, то удаляем папку, чтобы не смущала
        isEmpty := true
        Loop Files, backupDir . "\*.*" {
            isEmpty := false
            break
        }
        if isEmpty {
            try {
                DirDelete(backupDir)
            }
        }

        if CustomFileList
            SB.SetText("Патчинг завершен! Обработано файлов: " . ProcessedFiles.Length . " cм. папку \results\")
        else
            SB.SetText("Патчинг завершен! Обработано файлов: " . ProcessedFiles.Length)

    } catch as err {
        MsgBox("Ошибка: " . err.Message, "Ошибка", 16)
    }
}


ProcessFile(filePath, backupDir) {
    global ProcessedFiles, line

    line+=1

    SplitPath(filePath, &fileName)

    if !CustomFileList {
        relSysFilePath := A_ScriptDir . "\..\..\..\System\" . fileName
        SystemFile := ""
        Loop Files, relSysFilePath
        SystemFile := A_LoopFileFullPath


        ; Поиск в \L2\system
        if !FileExist(SystemFile) {
            FileListView.Modify(line, , fileName, "Не найден в system")
            return
        }

        ; Копирование в \temp
        try {
            FileCopy(SystemFile, "temp\" . fileName, 1)
        } catch {
            FileListView.Modify(line, , fileName, "Ошибка копирования в temp папку")
            return
        }

        ; Копирование в \backup
        try {
            FileCopy(SystemFile, backupDir . "\" . fileName, 1)
        } catch {
            FileListView.Modify(line, , fileName, "Ошибка сделать backup")
            return
        }

        ; Копирование в \orig
        try {
            FileCopy(SystemFile, A_ScriptDir . "\..\orig\system\" . fileName, 1)
        } catch {
            FileListView.Modify(line, , fileName, "Ошибка перезаписи в папку \orig")
            return
        }
    }
    else {
        ; Копирование в \temp файлов, полученных drag&drop-ом
        try {
            FileCopy(filePath, "temp\" . fileName, 1)
        } catch {
            FileListView.Modify(line, , fileName, "Ошибка копирования в temp папку")
            return
        }
    }

    ; Декодирование
    FileListView.Modify(line, , fileName, "Декодирование...")
    decFile := "temp\dec_" . fileName
    RunWait("l2encdec.exe -d temp\" . fileName . " " . decFile, , "Hide")


    if !FileExist(decFile) {
        FileListView.Modify(line, , fileName, "Ошибка декодирования")
        return
    }

    ; Сохраняем хеш оригинального декодированного файла
    originalDecHash := GetFileHash(decFile)

    ; Модификация файла
    FileListView.Modify(line, , fileName, "Модификация...")
    try {
        modifyResult := Patch(decFile, fileName)
        if (modifyResult = "NO_CHANGES_FILE") {
            FileListView.Modify(line, , fileName, "Нет исходников для патчевания")
            return
        }
    } catch as err {
        FileListView.Modify(line, , fileName, "Ошибка модификации")
        return
    }

    ; Сравниваем хеш декодированного файла до и после модификации
    modifiedDecHash := GetFileHash(decFile)
    if (originalDecHash = modifiedDecHash) {
        FileListView.Modify(line, , fileName, "Файл не изменен")
        return
    }

    ; Кодирование
    FileListView.Modify(line, , fileName, "Кодирование...")
    encFile := "temp\enc_dec_" . fileName
    RunWait("l2encdec.exe -e 211 " .  decFile . " " . encFile, , "Hide")

    if !FileExist(encFile) {
        FileListView.Modify(line, , fileName, "Ошибка кодирования")
        return
    }


    ; Переименование enc_dec_ файла
    try {
        FileDelete("temp\" . fileName)
        FileMove(encFile, "temp\" . fileName, 1)
    } catch {
        FileListView.Modify(line, , fileName, "Ошибка финального переименования")
        return
    }

    ; Перемещение в конечную директорию (Если скрипт был запущен из папки патча, то обновим сами файла патча в \files\system. Иначе просто сохраним в папку \results)
    if !CustomFileList {
        ; Сравниваем хеш нового файла с файлом в files\system
        targetFile := A_ScriptDir . "\..\files\system\" . fileName
        newFileHash := GetFileHash("temp\" . fileName)

        if FileExist(targetFile) {
            targetFileHash := GetFileHash(targetFile)
            if (newFileHash = targetFileHash) {
                FileListView.Modify(line, , fileName, "Файл в патче актуален")
                return
            }
        }

        try {
            FileCopy("temp\" . fileName, targetFile, 1)
            FileListView.Modify(line, , fileName, "Готово ✓")
            ProcessedFiles.Push(fileName)
        } catch {
            FileListView.Modify(line, , fileName, "Ошибка замены в \files\system\")
        }
    }
    else {
        try {
            if !DirExist("results")
                DirCreate("results")
            FileCopy("temp\" . fileName, A_ScriptDir . "\results\" . fileName, 1)
            FileListView.Modify(line, , fileName, "Готово ✓")
            ProcessedFiles.Push(fileName)
        } catch {
            FileListView.Modify(line, , fileName, "Ошибка замены в \results\")
        }
    }
}

Patch(decFilePath, fileName) {
    global line, SB

    ; Цикл по шагам от 1 до 9
    Loop 9 {
        stepNum := A_Index
        
        ; Формируем путь к файлу изменений для текущего шага
        if (stepNum = 1) {
            changesFile := A_ScriptDir . "\resources\changes_" . fileName
        } else {
            changesFile := A_ScriptDir . "\resources\step" . stepNum . "\changes_" . fileName
        }
        
        ; Проверяем существование файла изменений
        if !FileExist(changesFile) {
            ; Если это первый шаг и файла нет - возвращаем ошибку
            if (stepNum = 1) {
                return "NO_CHANGES_FILE"
            }
            ; Если это не первый шаг и файла нет - прерываем цикл
            else {
                break
            }
        }

        ; Читаем файл с изменениями
        changesContent := FileRead(changesFile)
        changes := Map()

        ; Подсчитываем количество строк в файле изменений
        totalChangesLines := 0
        Loop Parse, changesContent, "`n", "`r" {
            if (Trim(A_LoopField) != "")
                totalChangesLines++
        }

        ; Прогресс модификации в % отображаем только для diff-ов с 50+ строчками
        showProgress := (totalChangesLines > 50)
        
        ; Формируем текст статуса с учетом шага
        stepText := (stepNum = 1) ? "" : " Шаг " . stepNum . "..."
        
        if (showProgress) {
            SB.SetText("Выполняется модификация файла" . stepText . ": 0%")
        } else {
            SB.SetText("Модификация файла" . stepText . "...")
        }

        ; Парсим файл с изменениями
        Loop Parse, changesContent, "`n", "`r" {
            lineContent := Trim(A_LoopField)
            if (lineContent = "")
                continue

            ; Извлекаем ключ (первая пара key = value)
            parts := StrSplit(lineContent, "`t")
            if (parts.Length < 2)
                continue

            keyPart := Trim(parts[1])
            keyMatch := RegExMatch(keyPart, "(\w+)\s*=\s*(.+)", &m)
            if !keyMatch
                continue

            keyName := m[1]
            keyValue := Trim(m[2])

            ; Создаем Map для этого ключа, если его еще нет
            ; Структура: changes[keyValue] := Map("keyName" -> имя ключа, "replacements" -> Map замен)
            if !changes.Has(keyValue)
                changes[keyValue] := Map("keyName", keyName, "replacements", Map())

            ; Добавляем все остальные пары key = value для замены
            for i, part in parts {
                if (i = 1)
                    continue

                part := Trim(part)
                if RegExMatch(part, "(\w+)\s*=\s*(.+)", &m2) {
                    changes[keyValue]["replacements"][m2[1]] := Trim(m2[2])
                }
            }
        }

        ; Читаем исходный файл
        sourceContent := FileRead(decFilePath, "UTF-16")
        result := ""

        ; Подсчитываем строки в исходном файле для отображения прогресса
        totalSourceLines := 0
        Loop Parse, sourceContent, "`n", "`r" {
            totalSourceLines++
        }

        currentSourceLine := 0
        lastPercent := -1

        ; Обрабатываем каждую строку
        Loop Parse, sourceContent, "`n", "`r" {
            lineContent := A_LoopField
            currentSourceLine++

            ; Обновляем прогресс в StatusBar, если нужно
            if (showProgress && totalSourceLines > 0) {
                percent := Round(currentSourceLine / totalSourceLines * 100)
                ; Показываем только 0, 20, 40, 60, 80, 100
                displayPercent := Floor(percent / 20) * 20
                if (displayPercent != lastPercent) {
                    SB.SetText("Выполняется модификация файла" . stepText . ": " . displayPercent . "%")
                    lastPercent := displayPercent
                }
            }

            if (lineContent = "") {
                result .= lineContent "`r`n"
                continue
            }

            ; Парсим строку
            parts := StrSplit(lineContent, "`t")
            modified := false

            ; Ищем ключ в строке
            for keyValue, changeData in changes {
                found := false
                keyName := changeData["keyName"]
                replacements := changeData["replacements"]

                for i, part in parts {
                    ; Ищем совпадения вида: ключ=значение (без учета регистра)
                    escapedKeyValue := RegExReplace(keyValue, "([\[\]\{\}\(\)\.\+\*\?\^\$\|\\])", "\$1")
                    if RegExMatch(part, "i)^" keyName "\s*=\s*" escapedKeyValue "$") {
                        found := true
                        break
                    }
                }

                if found {
                    ; Заменяем значения
                    for i, part in parts {
                        for replaceKey, replaceValue in replacements {
                            ; Сохраняем оригинальное форматирование пробелов вокруг = (в skills* файлах обычно до и после = присутствуют пробелы, в других файлах обычно нет)
                            if RegExMatch(part, "i)^(" replaceKey ")(\s*=\s*)", &m) {
                                parts[i] := m[1] m[2] replaceValue
                                modified := true
                            }
                        }
                    }
                    break
                }
            }

            ; Собираем строку обратно
            newLine := ""
            for i, part in parts {
                if (i > 1)
                    newLine .= "`t"
                newLine .= part
            }
            ; CRLF
            result .= newLine "`r`n"
        }

        ; Удаляем последний перенос строки
        result := RTrim(result, "`r`n")

        ; Удаляем старый файл и записываем результат  (UTF-16 LE с BOM)
        FileDelete(decFilePath)
        FileAppend(result, decFilePath, "UTF-16")
    }
}

GetFileHash(filePath) {
    ; Вычисляем MD5 хеш файла (читаем как бинарные данные)
    file := FileOpen(filePath, "r")
    if !file
        return ""

    ; Читаем весь файл как бинарные данные
    file.Pos := 0
    fileSize := file.Length
    content := Buffer(fileSize)
    file.RawRead(content, fileSize)
    file.Close()

    ; MD5 алгоритм
    algId := 0x8003

    ; Получаем хендл провайдера
    hProv := 0
    if !DllCall("advapi32\CryptAcquireContext", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", 1, "UInt", 0xF0000000)
        return ""

    ; Создаем хеш объект
    hHash := 0
    if !DllCall("advapi32\CryptCreateHash", "Ptr", hProv, "UInt", algId, "Ptr", 0, "UInt", 0, "Ptr*", &hHash) {
        DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        return ""
    }

    ; Хешируем данные
    if !DllCall("advapi32\CryptHashData", "Ptr", hHash, "Ptr", content, "UInt", fileSize, "UInt", 0) {
        DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        return ""
    }

    ; Получаем размер хеша
    hashSize := 0
    sizeOfHashSize := 4
    if !DllCall("advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", 4, "UInt*", &hashSize, "UInt*", &sizeOfHashSize, "UInt", 0) {
        DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        return ""
    }

    ; Получаем хеш
    hashData := Buffer(hashSize)
    if !DllCall("advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", 2, "Ptr", hashData, "UInt*", &hashSize, "UInt", 0) {
        DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        return ""
    }

    ; Конвертируем в hex строку
    hashStr := ""
    loop hashSize {
        hashStr .= Format("{:02X}", NumGet(hashData, A_Index - 1, "UChar"))
    }

    ; Освобождаем ресурсы
    DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
    DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)

    return hashStr
}


Play(hwnd) => PostMessage(0x8001,,,, hwnd)
Restart(hwnd) => PostMessage(0x8001, 1,,, hwnd)
Pause(hwnd) => PostMessage(0x8002,,,, hwnd)
Stop(hwnd) => PostMessage(0x8002, 1,,, hwnd)
PlayPause(hwnd) => PostMessage(0x202,,,, hwnd)
RestartStop(hwnd) => PostMessage(0x202, 1,,, hwnd)
IsPlaying(hwnd) => DllCall("GetWindowLong", "ptr", hwnd, "int", 4*A_PtrSize, "ptr")
Step(hwnd, n) => PostMessage(0x8000, n,,, hwnd)
NextFrame(hwnd) => Step(hwnd, 1)
PrevFrame(hwnd) => Step(hwnd, -1)