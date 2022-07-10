---
title: Windows SSHD setup | Windows SSHD 配置
tags: [sshd, windows]
date: 2022-07-10 15:30:00
---

## Environment Prepare

I don't know if anyone else has noticed, Windows 10 has OpenSSH builtin. `sshd.exe` found in `C:\Windows\System32\OpenSSH`. It means now you can connect to windows using ssh.
> 不知道有没有人留意过, Windows 10 开始内置了 OpenSSH, 其中就有 `sshd.exe`. 也就是说, Windows 内置的 OpenSSH 拥有启动 SSHD 的功能.

After searching `Services`. I found `OpenSSH Server` in services. It is disabled by default.
> 在翻看服务列表后, 果然找到了 `OpenSSH Server`, 默认是需要手动启动的.

![](/static/imgs/windows-sshd-service.png)

Start the service, type `ssh karlatemp@::1`, type my password. Done!
> 在启动后, 执行 `ssh karlatemp@::1`, 输入密码, 成功登入

## Install or Update OpenSSH

[PowerShell/Win32-OpenSSH]: https://github.com/PowerShell/Win32-OpenSSH/releases

If your OS lower than Windows 10, you can just install it by open [PowerShell/Win32-OpenSSH]
> 如果你的系统不是 Windows 10, 那你也可以安装 OpenSSH 并启动 OpenSSH Server. 只需要打开 [PowerShell/Win32-OpenSSH] 安装一个就行

> You need download `OpenSSH-Win64.zip` (`-Win32` if 32-bit OS) not `.msi`,
> `.msi` may have no any response
>
> 需要下载 `OpenSSH-Win64.zip` (如果是 32 位就下载 `-Win32`) 而不是 `.msi`,
> `.msi` 也许会没有任何响应

A file named `install-sshd.ps1` exists in the lastest release of Microsoft's OpenSSH.
Just type `powershell C:\Windows\System32\install-sshd.ps1` in cmd (Administrator).
> 在下载的 zip 中有一个叫 `install-sshd.ps1` 的文件, 只需要执行上面这行命令就能安装 sshd (管理员模式)

## Troubleshooting

After `.ssh/authorized_keys` configed, type `ssh karlatemp@::1`, not working!!
> 在配置 `.ssh/authorized_keys` 后, 执行 `ssh karlatemp@::1`, 无用!!

After some searching, I found that OpenSSH's config located in `C:\ProgramData\ssh`, but nothing in logs.
> 在搜索后, 找到 OpenSSH 的配置文件在 `C:\ProgramData\ssh`, 在我满怀激动的打开 logs 文件夹后, 空的!


Change `sshd_config`
> 怀着激动的心情, 打开 `sshd_config` 找到了并修改了下面的东西

```
StrictModes no
PubkeyAuthentication yes
```

Restarting the service. Re-ssh again. Not working.
> 在重启服务后, 重新使用 ssh 链接, 依然需要密码

After switch `LogLevel DEBUG3`, Only a little information found in EventViewer.
> 在修改为 `LogLevel DEBUG3`, 在 EventViewer 中只有一点点有用的信息

![](/static/imgs/windows-sshd-event-viewer.png)

It means sshd received my ssh public key but sshd denied.
> 这意味着 sshd 收到了我的公钥但是她拒绝了

After type `sshd -?` in cmd, I found the `-E log_file`
> 在输入 `sshd -?` 后, 我找到了 `-E log_file` 这个选项

```
C:\ProgramData\ssh>sshd -?
unknown option -- ?
OpenSSH_for_Windows_8.9p1, LibreSSL 3.4.3
usage: sshd [-46DdeiqTt] [-C connection_spec] [-c host_cert_file]
            [-E log_file] [-f config_file] [-g login_grace_time]
            [-h host_key_file] [-o option] [-p port] [-u len]
```

Stop the `OpenSSH Server` service. Launch a temp sshd in cmd.
> 关闭 `OpenSSH Server` 后, 在一个 cmd 内启动一个临时的 sshd

```
## cmd1
B:\>C:\Windows\System32\OpenSSH\sshd.exe -E B:\tmp.log

## cmd2
B:\>ssh karlatemp@::1
karlatemp@::1's password:^C

B:\>

## cmd1 Ctrl+C
```

After analyzing `tmp.log`, I found:
> 在分析 `tmp.log` 后

```
debug2: parse_server_config_depth: config reprocess config len 2200
debug3: checking match for 'Group administrators' user karlatemp host 127.0.0.1 addr 127.0.0.1 laddr 127.0.0.1 lport 22
debug3: get_user_token - i am running as karlatemp, returning process token
debug1: user karlatemp matched group list administrators at line 87
debug3: match found
debug3: reprocess config:88 setting AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
..........................................................
debug2: input_userauth_request: try method publickey [preauth]
debug2: userauth_pubkey: valid user Karlatemp querying public key rsa-sha2-512 AAAAB3u........ [preauth]
..........................................
debug3: mm_answer_keyallowed: entering
debug1: trying public key file __PROGRAMDATA__/ssh/administrators_authorized_keys
debug3: Failed to open file:C:/ProgramData/ssh/administrators_authorized_keys error:2
debug1: Could not open authorized keys '__PROGRAMDATA__/ssh/administrators_authorized_keys': No such file or directory
debug3: mm_answer_keyallowed: publickey authentication test: RSA key is not allowed
Failed publickey for Karlatemp from 127.0.0.1 port 9431 ssh2: RSA SHA256:VCTkssQTyBJKQ6sg2BwIJYYnTYt3osJrHprxnGsJfB8
...........................................
debug2: input_userauth_request: try method publickey [preauth]
debug2: userauth_pubkey: valid user Karlatemp querying public key ecdsa-sha2-nistp521 AAAAE2VjZHN....... [preauth]
debug1: userauth_pubkey: publickey test pkalg ecdsa-sha2-nistp521 pkblob ECDSA SHA256:zPVO........ [preauth]
debug3: mm_key_allowed: entering [preauth]
..................................
debug1: trying public key file __PROGRAMDATA__/ssh/administrators_authorized_keys
debug3: Failed to open file:C:/ProgramData/ssh/administrators_authorized_keys error:2
debug1: Could not open authorized keys '__PROGRAMDATA__/ssh/administrators_authorized_keys': No such file or directory
debug3: mm_answer_keyallowed: publickey authentication test: ECDSA key is not allowed
Failed publickey for Karlatemp from 127.0.0.1 port 9431 ssh2: ECDSA SHA256:zPVOOjAvI0/F2dsFT346uFev5cOpKSlEsPFt5ZiSezU
.....................................
debug1: attempt 4 failures 3 [preauth]
debug2: input_userauth_request: try method password [preauth]

```

View `sshd_config` again, found in last
> 再认真看一次 `sshd_config`, 在末尾找到了

```
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

After disabling it and restarting the OpenSSH Server service. Success to login~~
> 禁用掉后, 重启服务, 一切运行正常~~
