# Generated from trgen <version>

$TestDirectory = "<if(os_win)>../<example_files_win><else>../<example_files_unix><endif>"
Write-Host "Test cases here: $TestDirectory"

# People often specify a test file directory, but sometimes no
# tests are provided. Git won't check in an empty directory.
# Test if the test file directory does not exist, or it is just
# an empty directory.
if (!(Test-Path -Path "$TestDirectory")) {
    Write-Host "No test cases provided."
    exit 0
} elseif (!(Test-Path "$TestDirectory/*")) {
    Write-Host "No test cases provided."
    exit 0
}

# Get a list of test files from the test directory. Do not include any
# .errors or .tree files. Pay close attention to remove only file names
# that end with the suffix .errors or .tree.
if (Test-Path -Path "tests.txt" -PathType Leaf) {
    Remove-Item "tests.txt"
}
$files = New-Object System.Collections.Generic.List[string]
foreach ($item in Get-ChildItem $TestDirectory -Recurse) {
    $file = $item.fullname
    $ext = $item.Extension
    if (Test-Path $file -PathType Container) {
        continue
    } elseif ($ext -eq ".errors") {
        continue
    } elseif ($ext -eq ".tree") {
        continue
    } else {
        $(& triconv -f utf-8 $file ; $last = $LASTEXITCODE ) | Out-Null
        if ($last -ne 0)
        {
            continue
        }
        $files.Add($item)
        Write-Host "Test case: $item"
    }
}
foreach ($file in $files) {
    Add-Content "tests.txt" $file
}
if (-not(Test-Path -Path "tests.txt" -PathType Leaf)) {
    Write-Host "No test cases provided."
    exit 0
}

# Parse all input files.
get-content "tests.txt" | trwdog python3 Test.py -q -x -tee -tree *> parse.txt
$status = $LASTEXITCODE

# trwdog returns 255 if it cannot spawn the process. This could happen
# if the environment for running the program does not exist, or the
# program did not build.
if ( $status -eq 255 ) {
    Write-Host "Test failed."
    Get-Content $file | Write-Host
    exit 1
}

# Any parse errors will be put in .errors files. But, if there's any
# output from the program in stdout or stderr, it's all bad news.
$size = (Get-Item -Path "parse.txt").Length
if ( $size -eq 0 ) {
} else {
    Write-Host "Test failed."
    Get-Content "parse.txt" | Write-Host
    exit 1
}

# Check if any .errors/.tree files have changed. That's not good.
$message = git diff --exit-code --name-only $TestDirectory
$updated = $LASTEXITCODE
Write-Host $message

# Check if any untracked .errors files are not empty.
$new_errors_txt = New-Object System.Collections.Generic.List[string]
$new_errors2_txt = git ls-files --exclude-standard -o --ignored $TestDirectory
$new_errors = $LASTEXITCODE

# Gather up all untracked .errors file output. These are new errors
# and must be reported as a parse fail.
if ( ! [String]::IsNullOrWhiteSpace($new_errors2_txt) ) {
    $new_errors3_txt = $new_errors2_txt.Split("\n\r\t ")
} else {
    $new_errors3_txt = [System.Collections.Arraylist]@()
}
if (Test-Path -Path "new_errors.txt" -PathType Leaf) {
    Remove-Item "new_errors.txt"
}
New-Item -Path . -Name "new_errors.txt" -ItemType "file" -Value "" | Out-Null
foreach ($s in $new_errors3_txt) {
    if ( [String]::IsNullOrWhiteSpace($s) ) {
        continue
    }
    $ext = $item.Extension
    if (! $s.EndsWith(".errors")) {
        continue
    }
    $file = $s
    $size = (Get-Item -Path $file).Length
    if ( $size -eq 0 ) {
    } else {
        $new_errors_txt.Add($item)
        Add-Content -Path "new_errors.txt" -Value "$item"
        ((Get-Content $file) -join "`n") + "`n" | Add-Content -Path "new_errors.txt"
    }
}

# If "git diff" reported an exit code of 129, it is because
# the directory containing the grammar is not in a repo. In this
# case, assume parse error code as the defacto result.
if ( $updated -eq 129 ) {
    Write-Host "Grammar outside a git repository. Assuming parse exit code."
    if ( $status -eq 0 ) {
        Write-Host "Test succeeded."
    } else {
        Get-Content "new_errors.txt" | Write-Host
        Write-Host "Test failed."
    }
    $err = $status
    exit 1
}

# "Git diff" reported a difference. Redo the "git diff" to print out all
# the differences. Also, output any untracked, non-zero length .errors files.
if ( $updated -eq 1 ) {
    Write-Host "Difference in output."
    git diff . | Write-Host
    Get-Content "new_errors.txt" | Write-Host
    Write-Host "Test failed."
    exit 1
}

# If there's non-zero length .errors flies that are new, report them
# as errors in the parse.
if ( $new_errors_txt.Count -gt 0 ) {
    Write-Host "New errors in output."
    Get-Content "new_errors.txt" | Write-Host
    Write-Host "Test failed."
    exit 1
}

Write-Host "Test succeeded."
exit 0