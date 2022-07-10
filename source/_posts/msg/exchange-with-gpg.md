---
title: 使用 GnuPG 在公开平台交换数据
date: 2022-07-10 15:00:00
categories: [msg]
tags: [gpg, msg-exchange]
---

## 环境准备

- GPG

> 对于 Windows, `Git for Windows` 自带 GPG 支持
>
> ```
> B:\test>where base64
> F:\Exes\Git\usr\bin\base64.exe
> F:\Exes\cygwin64\bin\base64.exe
>
> B:\test>where gpg
> F:\Exes\Git\usr\bin\gpg.exe
>
> B:\test>where curl
> C:\Windows\System32\curl.exe
> ```

## 确定信息要发送的目标

首先需要确定信息要发给哪个人, 然后你需要向你需要发送的目标问到她的 GPG 公钥

在问到 GPG 公钥后, 可使用 `gpg --import publickey.txt` 来导入她的 GPG 公钥

> 对于 GitHub, 你可以通过 `https://github.com/${username}.gpg` 来得到她的 GPG 公钥
>
> 比如, 如果你想给 Karlatemp 交换私密消息, 你可以通过打开 `https://github.com/Karlatemp.gpg` 来得到 Karlatemp 的 GPG 公钥

> 可以执行 `gpg --list-keys` 来查看需要发送的目标的邮箱 / keyid

## 加密要发送的内容

现在我们有一段文本需要发送给 Karlatemp, 文件的名字是 `test.txt`

```txt
// Hi karlatemp
fun main() {
    println("Never gonna give you up.")
}
```

执行以下命令, 我们可以得到一份可以公开发布的已加密文件 `test.txt.gpg`

```
B:\test>gpg --out test.txt.gpg --encrypt test.txt
You did not specify a user ID. (you may use "-r")

Current recipients:

Enter the user ID.  End with an empty line: kar@kasukusakura.com

Current recipients:
rsa4096/676CA4DC58342C11 2022-05-21 "Karlatemp <kar@kasukusakura.com>"

Enter the user ID.  End with an empty line:

B:\test>ls
test.txt  test.txt.gpg
```

但是 `test.txt.gpg` 是二进制编码的, 如果需要将她直接粘贴到评论区的话, 可以进行一次 base64 转换

```
B:\test>base64 test.txt.gpg > test.txt.gpg.b64

```

现在可以将 `test.txt.gpg.b64` 直接粘贴到评论区了 (记得说明这是一份经过 base64 编码的 gpg 文件)

## 解密收到的内容

现在我收到了一份 `test.txt.gpg.b64`, 首先一看, `b64` 结尾, 需要先进行 base64 解码回原始二进制数据

```
B:\text>base64 -d test.txt.gpg.b64 > test.txt.gpg
```

现在可以查看收到的是什么信息了

```
B:\test>gpg --output - --decrypt test.txt.gpg
gpg: encrypted with 4096-bit RSA key, ID 676CA4DC58342C11, created 2022-05-21
      "Karlatemp <kar@kasukusakura.com>"
// Hi karlatemp
fun main() {
    println("Never gonna give you up.")
}
B:\test>
```

> `--output -` 意义为将解码结果直接输出到控制台,
> 可以更换成 `--output test.txt` 来将结果输出到 `test.txt`
