
$Path = (Split-Path $MyInvocation.MyCommand.Path)
$Mod = $Path + '\ImportExcel' 
$csv = $Path + '\*.csv'

# 安裝excel 模組
Import-Module $Mod

# 獲取最新Patch Excel File
$excelUrl = "https://aka.ms/sqlserverbuilds"
$Path = (Split-Path $MyInvocation.MyCommand.Path)
$date = (get-date).ToString('yyyyMMddHHmmss')
$excel = $Path + "\sqlserverbuilds_$date.xlsx"
$out = $path + "\" + "SQLPATCH_" + $date + ".csv" 
Invoke-WebRequest -Uri $excelUrl -OutFile $excel


# 獲取EXCEL頁面名稱
$ver = 2022, 2019, 2017, 2016, 2014, 2012, '2008 R2', 2008, 2005

# 取最新的資料作整理
$table = @()
foreach ($v in $ver) {
    $SQLPatchData = Import-Excel $excel -WorksheetName $v
    $table += $SQLPatchData | where-object { $_.'KB Number' -notin ('NA', 'N/A') } |`
        select-object `
    @{Name = 'SQLServer'; expression = { $v } }, `
    @{name = 'KBName'; expression = { 'KB' + $_.'KB Number' } }, `
    @{name = 'LatestPatchDate'; expression = { ([DateTime]::FromOADate($_.'Release Date')).ToString('yyyy-MM-dd') } }, `
    @{name = 'LatestPatchName'; expression = { $_.'Cumulative Update or Security ID' } }, `
    @{name = 'URL'; expression = { $_.'KB URL' } } | sort-object LatestPatchDate -desc | select-object -first 1
} 

# 輸出Table
$table | ConvertTo-Csv -NoTypeInformation > $out

Get-ChildItem ($Path+'\*.xlsx') | sort-object LastWriteTime -desc | select-object -skip 2 | Remove-Item -Force     
Get-ChildItem $csv | sort-object LastWriteTime -desc | select-object -skip 2 | Remove-Item -Force     


