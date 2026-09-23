' keepalive.vbs —— Windows 侧保活：定时唤醒 WSL，防止发行版被空闲回收
'
' 背景：WSL2 发行版在空闲后会被回收，vmmem 进程退出 → WSL 里的 systemd 服务
'       随发行版一起消失，Host 就断了。.wslconfig 的 instanceIdleTimeout 实测
'       并不总能生效，所以用这个脚本每 5 分钟"戳"一下 WSL 保活。
'
' 用法：
'   1) 把本文件放进启动目录（Win+R 输入 shell:startup 回车）
'   2) 或直接双击运行
' 停止：任务管理器里结束 wscript.exe

Set sh = CreateObject("WScript.Shell")
Do While True
    ' 静默执行（0 = 隐藏窗口，False = 不等待）
    On Error Resume Next
    sh.Run "wsl.exe -d Ubuntu -- exec true", 0, False
    On Error GoTo 0
    WScript.Sleep 300000   ' 5 分钟
Loop
