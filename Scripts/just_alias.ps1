#requires -Version 7.0
<#
    just_alias.ps1 — общий код для команд, работающих с псевдонимами из just:
      go_dir, j_edit, j_tail   — ЧИТАЮТ псевдоним (рецепт группы печатает путь);
      just_dir, just_file      — ДОБАВЛЯЮТ псевдоним в local.just.

    Сам по себе ничего не делает: его подключают эти команды (каждая сама, дот-сорсингом
    рядом лежащего файла). Псевдоним — рецепт just из группы, который печатает ОДИН путь:

        # Проект
        [group('j_file')]
        file_nginx:
            @echo 'C:\nginx\conf\nginx.conf'

    Рецепт без параметров и не [private] (приватные скрыты из `just --list`, по нему
    и строится список). Источник — всегда глобальный justfile (`just -g`).

    JUST_ALIAS_JUSTFILE — служебная переменная для отладки: если задана, вместо -g
    берётся этот justfile.
#>

# хелперы just_new: каталог конфигов, разбор имён рецептов, удаление рецепта
if (-not (Get-Command Get-JnConfigDir -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'just_new.ps1')
}

# ===========================================================================
# Чтение
# ===========================================================================

# just с глобальным justfile либо с файлом из JUST_ALIAS_JUSTFILE
function Invoke-JaJust {
    param([string[]] $JustArgs)
    $exe = (Get-Command just -CommandType Application | Select-Object -First 1).Source
    if ($env:JUST_ALIAS_JUSTFILE) {
        & $exe --justfile $env:JUST_ALIAS_JUSTFILE --working-directory . @JustArgs
    } else {
        & $exe -g @JustArgs
    }
}

# рецепты группы: объекты {Name, Description}
function Get-JaAlias {
    param([string] $Group)

    $lines = Invoke-JaJust -JustArgs @('--list', '--unsorted', '--color', 'never',
                                       '--list-heading', '', '--list-prefix', '') 2>$null
    $cur = $null
    foreach ($raw in $lines) {
        $line = "$raw".TrimEnd("`r")
        if ($line -match '^\[(.+)\]$') { $cur = $Matches[1]; continue }
        if ($line -match '^\s*$')      { continue }
        if ($cur -ne $Group)           { continue }
        # имя без параметров, затем необязательное « # описание»
        if ($line -match '^(\S+)(?:\s+#\s*(.*))?$') {
            $desc = "$($Matches[2])" -replace '\s*\[alias: [^\]]*\]$', ''
            [pscustomobject]@{ Name = $Matches[1]; Description = $desc }
        }
    }
}

# команда вызвана без аргумента: список псевдонимов группы
function Show-JaList {
    param([string] $Caller, [string] $Group)
    $aliases = @(Get-JaAlias $Group)
    if (-not $aliases) { Write-Error "${Caller}: в justfile нет рецептов группы $Group"; return }
    $aliases | ForEach-Object { '  {0,-20} {1}' -f $_.Name, $_.Description }
}

# Путь, на который указывает псевдоним; при любой неудаче — ошибка и $null.
# Запускается только рецепт этой группы: иначе `go_dir restart` выполнил бы
# произвольный рецепт, а не перешёл в каталог.
function Resolve-JaAlias {
    param([string] $Caller, [string] $Group, [string] $Alias)

    $aliases = @(Get-JaAlias $Group)
    if ($Alias -notin $aliases.Name) {
        $msg = "${Caller}: «$Alias» — не псевдоним (группа $Group)."
        if ($aliases) {
            $msg += " Доступные:`n" + (($aliases | ForEach-Object { '  {0,-20} {1}' -f $_.Name, $_.Description }) -join "`n")
        } else {
            $msg += ' В justfile нет таких рецептов.'
        }
        Write-Error $msg
        return $null
    }

    # stdout рецепта — путь; stderr (строка `echo ...` без @) показываем только при ошибке
    $raw  = Invoke-JaJust -JustArgs @('--', $Alias) 2>&1
    $code = $LASTEXITCODE
    $err  = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $out  = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
                     ForEach-Object { "$_".Trim() } | Where-Object { $_ })

    if ($code -ne 0) {
        Write-Error ("${Caller}: рецепт $Alias завершился с ошибкой (код $code):`n" + ($err -join "`n"))
        return $null
    }
    if ($out.Count -ne 1) {
        Write-Error "${Caller}: рецепт $Alias должен печатать один путь, а напечатал строк: $($out.Count)"
        return $null
    }

    $path = $out[0]
    # кавычки в `echo '~/x'` блокируют раскрытие тильды — делаем это сами
    if ($path -eq '~' -or $path.StartsWith('~/') -or $path.StartsWith('~\')) { $path = $HOME + $path.Substring(1) }
    return $path
}

# варианты дополнения для Register-ArgumentCompleter: имена группы с описанием в подсказке
function Get-JaCompletion {
    param([string] $Group, [string] $WordToComplete)
    Get-JaAlias $Group | Where-Object { $_.Name -like "$WordToComplete*" } | ForEach-Object {
        $tip = if ($_.Description) { $_.Description } else { $_.Name }
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $tip)
    }
}

# ===========================================================================
# Запись (just_dir, just_file)
# ===========================================================================

# имя по умолчанию: <префикс><последний компонент пути>, только допустимые символы
function Get-JaDefaultName {
    param([string] $Prefix, [string] $Path)
    # GetFileName, а не Split-Path: у корня диска (C:\) тот берёт текущий каталог
    $leaf = [IO.Path]::GetFileName($Path.TrimEnd('\', '/'))
    $slug = ($leaf -replace '[^a-zA-Z0-9_-]+', '_').Trim('_')
    if (-not $slug -and $Path -match '^([a-zA-Z]):') { $slug = $Matches[1].ToUpper() }   # C:\ -> dir_C
    if (-not $slug) { $slug = 'root' }
    return "$Prefix$slug"
}

# блок рецепта: описание, атрибут группы, имя, путь
function New-JaBlock {
    param([string] $Name, [string] $Desc, [string] $Target, [string] $Group)

    # {{ }} в just — подстановка; литеральные скобки экранируются удвоением
    $path = $Target -replace '\{\{', '{{{{'

    $lines = @('')
    if ($Desc) { $lines += "# $Desc" }
    $lines += "[group('$Group')]"
    $lines += "${Name}:"
    $lines += "    @echo '$path'"
    return $lines
}

# Разбирает путь и имя и дописывает рецепт в local.just. Вид задаёт отличия: у dir путь
# по умолчанию — текущий каталог и проверяется каталог; у file путь обязателен и
# проверяется обычный файл.
function Add-JustAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Caller,
        [Parameter(Mandatory)] [string] $Group,
        [Parameter(Mandatory)] [ValidateSet('dir', 'file')] [string] $Kind,
        [string] $Path,
        [string] $Name,
        [string] $Desc,
        [switch] $Print,
        [switch] $Force
    )

    $noun   = if ($Kind -eq 'dir') { 'каталог' } else { 'файл' }
    $prefix = if ($Kind -eq 'dir') { 'dir_' } else { 'file_' }

    $configDir = Get-JnConfigDir
    $localFile = Join-Path $configDir 'local.just'
    $justFile  = Join-Path $configDir 'justfile'
    $repo      = Get-JnState 'JUST_REPO'

    if (-not (Test-Path -LiteralPath $justFile)) {
        Write-Error "нет $justFile — сначала выполните .\init.ps1 <группа>"
        return
    }

    # --- путь ---
    if ($Kind -eq 'file' -and -not $Path) {
        Write-Error "${Caller}: укажите файл: $Caller <файл>"
        return
    }
    if (-not $Path) {
        $target = (Get-Location).ProviderPath
    } else {
        # кавычки блокируют раскрытие тильды — делаем это сами
        if ($Path -eq '~' -or $Path.StartsWith('~/') -or $Path.StartsWith('~\')) { $Path = $HOME + $Path.Substring(1) }
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($Kind -eq 'dir') {
            if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)) {
                Write-Error "${Caller}: каталога нет: $Path"
                return
            }
        } else {
            if ($resolved -and (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)) {
                Write-Error "${Caller}: это каталог, а не файл: $Path (для каталогов есть just_dir)"
                return
            }
            if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Leaf)) {
                Write-Error "${Caller}: файла нет: $Path"
                return
            }
        }
        $target = $resolved.ProviderPath
    }
    if ($target.Contains("'")) {
        Write-Error "${Caller}: в пути есть одинарная кавычка, такой путь не поддерживается: $target"
        return
    }
    Write-Host "${noun}: $target"

    # --- имя псевдонима ---
    $default = Get-JaDefaultName -Prefix $prefix -Path $target
    if (-not $Name) {
        $answer = Read-JnInput "имя псевдонима [$default]"
        if ($null -eq $answer) {
            Write-Error "${Caller}: нет имени псевдонима: в неинтерактивной оболочке передайте -Name"
            return
        }
        $Name = if ($answer.Trim()) { $answer.Trim() } else { $default }
    }
    if ($Name -notmatch '^[a-zA-Z_][a-zA-Z0-9_-]*$') {
        Write-Error "${Caller}: недопустимое имя псевдонима: «$Name»"
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
        Write-Host "${Caller}: «$Name» — это alias в $aliasHit.just." -ForegroundColor Yellow
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
        Write-Host '  в другое место, чем на остальных.'
        Write-Host "  Общий псевдоним правят в $repo\Config — отсюда туда $Caller не пишет."
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
                        Write-Error "${Caller}: недопустимое имя псевдонима: «$Name»"
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
    $block = New-JaBlock -Name $Name -Desc $Desc -Target $target -Group $Group
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
        if ($Kind -eq 'dir') {
            Write-Host "перейти: go_dir $Name"
        } else {
            Write-Host "открыть: j_edit $Name"
            Write-Host "смотреть: j_tail $Name"
        }
    } else {
        Copy-Item -LiteralPath $backup -Destination $localFile -Force
        Remove-Item -LiteralPath $backup -Force
        Write-Host "${Caller}: just не разобрал результат, изменения отменены:" -ForegroundColor Red
        & just --justfile $justFile --working-directory . --summary
    }
}
