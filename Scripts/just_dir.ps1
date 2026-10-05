#requires -Version 7.0
<#
    just_dir.ps1 — сохранить каталог как псевдоним для go_dir.
    Парный к just_new: тот сохраняет команду, этот — каталог.

    Подключение (это делает init.ps1 -WithShell):
        . C:\путь\к\репозиторию\Scripts\just_dir.ps1

    Использование:
        just_dir                              псевдоним для текущего каталога
        just_dir C:\srv\app                   псевдоним для указанного каталога
        just_dir -Name app -Desc 'Проект'     имя и описание без вопросов
        just_dir -Print                       только напечатать блок, ничего не писать
        just_dir -Force                       не переспрашивать при конфликте имён

    Пишет ровно в один файл — local.just в каталоге конфигов (как just_new): путь
    принадлежит этой машине. Файлы репозитория (Config\global.just, Config\<группа>\
    group.just) правятся редактором из каталога проекта; для переноса туда есть -Print.

    Результат — рецепт группы go_dir, который печатает путь:

        # Проект
        [group('go_dir')]
        dir_app:
            @echo 'C:\srv\app'

    Перейти по нему: go_dir dir_app.
#>

# хелперы just_new: каталог конфигов, разбор имён рецептов, удаление рецепта
if (-not (Get-Command Get-JnConfigDir -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'just_new.ps1')
}

# имя по умолчанию: dir_<последний компонент пути>, только допустимые символы
function Get-JdDefaultName {
    param([string] $Path)
    # GetFileName, а не Split-Path: у корня диска (C:\) тот берёт текущий каталог
    $leaf = [IO.Path]::GetFileName($Path.TrimEnd('\', '/'))
    $slug = ($leaf -replace '[^a-zA-Z0-9_-]+', '_').Trim('_')
    if (-not $slug -and $Path -match '^([a-zA-Z]):') { $slug = $Matches[1].ToUpper() }   # C:\ -> dir_C
    if (-not $slug) { $slug = 'root' }
    return "dir_$slug"
}

# блок рецепта: описание, атрибут группы, имя, путь
function New-JdBlock {
    param([string] $Name, [string] $Desc, [string] $Dir)

    # {{ }} в just — подстановка; литеральные скобки экранируются удвоением
    $path = $Dir -replace '\{\{', '{{{{'

    $lines = @('')
    if ($Desc) { $lines += "# $Desc" }
    $lines += "[group('go_dir')]"
    $lines += "${Name}:"
    $lines += "    @echo '$path'"
    return $lines
}

function just_dir {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Path,
        [string] $Name,
        [string] $Desc,
        [switch] $Print,
        [switch] $Force
    )

    $configDir = Get-JnConfigDir
    $localFile = Join-Path $configDir 'local.just'
    $justFile  = Join-Path $configDir 'justfile'
    $repo      = Get-JnState 'JUST_REPO'

    if (-not (Test-Path -LiteralPath $justFile)) {
        Write-Error "нет $justFile — сначала выполните .\init.ps1 <группа>"
        return
    }

    # --- путь: аргумент или текущий каталог ---
    if (-not $Path) {
        $dir = (Get-Location).ProviderPath
    } else {
        # кавычки блокируют раскрытие тильды — делаем это сами
        if ($Path -eq '~' -or $Path.StartsWith('~/') -or $Path.StartsWith('~\')) { $Path = $HOME + $Path.Substring(1) }
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)) {
            Write-Error "just_dir: каталога нет: $Path"
            return
        }
        $dir = $resolved.ProviderPath
    }
    if ($dir.Contains("'")) {
        Write-Error "just_dir: в пути есть одинарная кавычка, такой путь не поддерживается: $dir"
        return
    }
    Write-Host "каталог: $dir"

    # --- имя псевдонима ---
    $default = Get-JdDefaultName $dir
    if (-not $Name) {
        $answer = Read-JnInput "имя псевдонима [$default]"
        if ($null -eq $answer) {
            Write-Error 'just_dir: нет имени псевдонима: в неинтерактивной оболочке передайте -Name'
            return
        }
        $Name = if ($answer.Trim()) { $answer.Trim() } else { $default }
    }
    if ($Name -notmatch '^[a-zA-Z_][a-zA-Z0-9_-]*$') {
        Write-Error "just_dir: недопустимое имя псевдонима: «$Name»"
        return
    }
    if (-not $PSBoundParameters.ContainsKey('Desc')) {
        $Desc = Read-JnInput 'описание (Enter — пропустить)'
        if ($null -eq $Desc) { $Desc = '' } else { $Desc = $Desc.Trim() }
    }

    # --- проверка имени по всем трём файлам ---
    $inLocal  = $Name -in (Get-JnRecipeNames (Join-Path $configDir 'local.just'))
    $inGroup  = $Name -in (Get-JnRecipeNames (Join-Path $configDir 'group.just'))
    $inGlobal = $Name -in (Get-JnRecipeNames (Join-Path $configDir 'global.just'))

    $aliasHit = $null
    foreach ($label in @('global', 'group', 'local')) {
        if ($Name -in (Get-JnAliasNames (Join-Path $configDir "$label.just"))) { $aliasHit = $label; break }
    }
    if ($aliasHit) {
        Write-Host "just_dir: «$Name» — это alias в $aliasHit.just." -ForegroundColor Yellow
        Write-Host '  Дубликаты алиасов just не прощает: конфиг перестанет разбираться целиком.'
        Write-Host '  Возьмите другое имя.'
        return
    }

    if ($inGroup -or $inGlobal) {
        $src = if ($inGroup -and $inGlobal) { 'group.just и global.just' }
               elseif ($inGroup) { 'group.just' } else { 'global.just' }
        Write-Host ''
        Write-Host "  ВНИМАНИЕ: рецепт «$Name» приезжает из репозитория ($src)." -ForegroundColor Yellow
        Write-Host '  Запись в local.just создаст локальное переопределение: local импортируется'
        Write-Host '  первым, а just берёт первое определение. На этой машине псевдоним поведёт'
        Write-Host '  в другой каталог, чем на остальных.'
        Write-Host "  Общий псевдоним правят в $repo\Config — отсюда туда just_dir не пишет."
        Write-Host ''
        if (-not $Print -and -not $Force) {
            $answer = Read-JnInput 'переопределить локально? [y/N/имя другого псевдонима]'
            if ($null -eq $answer) {
                Write-Host 'отменено: подтвердить перекрытие в неинтерактивной оболочке можно ключом -Force'
                return
            }
            switch -Regex ($answer) {
                '^(y|Y|yes|да)$' { }
                '^(|n|N|no|нет)$' { Write-Host 'отменено'; return }
                default {
                    $Name = $answer.Trim()
                    if ($Name -notmatch '^[a-zA-Z_][a-zA-Z0-9_-]*$') {
                        Write-Error "just_dir: недопустимое имя псевдонима: «$Name»"
                        return
                    }
                    $inLocal = $Name -in (Get-JnRecipeNames $localFile)
                }
            }
        }
    }

    if ($inLocal -and -not $Print -and -not $Force) {
        $answer = Read-JnInput "рецепт «$Name» уже есть в local.just, заменить? [y/N]"
        if ($null -eq $answer) {
            Write-Host 'отменено: заменить в неинтерактивной оболочке можно ключом -Force'
            return
        }
        if ($answer -notmatch '^(y|Y|yes|да)$') { Write-Host 'отменено'; return }
    }

    # --- вывод или запись ---
    $block = New-JdBlock -Name $Name -Desc $Desc -Dir $dir
    if ($Print) {
        Write-Host ''
        Write-Host '--- блок для вставки ---'
        $block | ForEach-Object { Write-Host $_ }
        Write-Host '------------------------'
        return
    }

    if (-not (Test-Path -LiteralPath $localFile)) {
        [IO.File]::WriteAllText($localFile, "# local.just — алиасы только этой машины.`n", [Text.UTF8Encoding]::new($false))
    }
    $backup = "$localFile.bak"
    Copy-Item -LiteralPath $localFile -Destination $backup -Force

    if ($inLocal) { [void] (Remove-JnRecipe -Path $localFile -Name $Name) }
    # после удаления рецепта в конце файла остаются пустые строки, а блок начинается
    # с пустой — без этого между рецептами получилось бы две
    $current = [IO.File]::ReadAllText($localFile).TrimEnd() + "`n"
    [IO.File]::WriteAllText($localFile, $current + (($block -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

    & just --justfile $justFile --working-directory . --summary *> $null
    if ($LASTEXITCODE -eq 0) {
        Remove-Item -LiteralPath $backup -Force
        Write-Host "записано в $localFile"
        if ($inGroup -or $inGlobal) {
            $loser = if ($inGlobal) { 'global.just' } else { 'group.just' }
            Write-Host "${Name}: local.just перекрывает $loser"
        }
        Write-Host "перейти: go_dir $Name"
    } else {
        Copy-Item -LiteralPath $backup -Destination $localFile -Force
        Remove-Item -LiteralPath $backup -Force
        Write-Host 'just_dir: just не разобрал результат, изменения отменены:' -ForegroundColor Red
        & just --justfile $justFile --working-directory . --summary
    }
}
