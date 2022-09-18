---
title: Gradle with JDK18+ 中文乱码配置
tags: [gradle, jvm]
date: 2022-09-18 23:03:00
---

在 Java18 之后, 当使用 `System.out.println()` 输出中文的时候, 不管源码是不是以 utf8 编译,
无论执行的代码是否是预编译的代码, 只能得到一个结果: 乱码


在经历了长时间的更新换代之后, 终于, `Gradle with JDK 18+`, 又又又又又乱码了!

## 分析

我首先想到了是不是需要额外加一个 vm option `-Dfile.encoding=UTF-8`, 然后我在 IDEA 里的运行任务加上了这个参数.... 并没有什么效果

依然得到的还是乱码....

后面又去检查了 `gradle.properties`, `idea64.vmoptions`, 都是附带 `-Dfile.encoding=UTF8` 的... 是什么原因呢?


然后我突然想起来, 在 Gradle 项目中, 在 IDEA 里运行 java main 目标其实是由 Gradle 启动的而不是由 IDEA 直接启动的, 并且 Gradle 是有运行日志的, 然后我直接就打开了 Gradle 目录并找到了日志

> - Gradle 的日志位于 `$GRADLE_USER_HOME/daemon/$version/daemon-$pid.out.log`
> - 与 Kotlin 项目不同的是, `Gradle with Java` 的 main 启动是由 Gradle 启动的, 而 Kotlin main 是直接由 IDEA 启动的

翻了一下日志, 很快就找到了上次执行程序的输出

定位到日志点之后, 使用别的编码再重新打开 (UTF8, GBK, GB 2312...), 都是乱码.

于是推测 `Java18 main -> Gradle` 的时候输出格式已经乱掉了

于是有了一个大胆的推测:

> 编译之后的字节码文件是没问题的, 而是执行的时候输出到控制台的时候就乱码了

然后我再用 IDEA 写了一个只有 `println` 的类与方法, 然后直接使用 `$JDK18_HOME/bin/java.exe` 执行, 在 `cmd.exe` 得到的结果是正常的中文

这就成功证实了是 `Java18 main -> Gradle` 的时候出现了问题


最后翻阅 `src.zip/java.bases/java/lang/System.java`, 分析了一下 `System.out` 的初始化流程


```java
// System.java

    /**
     * Initialize the system class.  Called after thread initialization.
     */
    private static void initPhase1() {
        // ......

        FileInputStream fdIn = new FileInputStream(FileDescriptor.in);
        FileOutputStream fdOut = new FileOutputStream(FileDescriptor.out);
        FileOutputStream fdErr = new FileOutputStream(FileDescriptor.err);
        setIn0(new BufferedInputStream(fdIn));
        // sun.stdout/err.encoding are set when the VM is associated with the terminal,
        // thus they are equivalent to Console.charset(), otherwise the encoding
        // defaults to native.encoding
        setOut0(newPrintStream(fdOut, props.getProperty("sun.stdout.encoding", StaticProperty.nativeEncoding())));
        setErr0(newPrintStream(fdErr, props.getProperty("sun.stderr.encoding", StaticProperty.nativeEncoding())));

        // ......
    }

```

```java
// StaticProperty.java
    private static final String NATIVE_ENCODING;

    static {
        NATIVE_ENCODING = getProperty(props, "native.encoding");
    }

    /**
     * {@return the {@code native.encoding} system property}
     *
     * <strong>{@link SecurityManager#checkPropertyAccess} is NOT checked
     * in this method. The caller of this method should take care to ensure
     * that the returned property is not made accessible to untrusted code.</strong>
     */
    public static String nativeEncoding() {
        return NATIVE_ENCODING;
    }

```

最后分析得 Java 根据 `sun.stdout.encoding`, `sun.stderr.encoding`, `native.encoding` 确定 stdout 编码

然后在 IDEA 里把这三个值打印出来

```java
public class RwB {

    public static void main(String[] args) throws Throwable {
        System.out.println("sun.stdout.encoding = " + System.getProperty("sun.stdout.encoding"));
        System.out.println("sun.stderr.encoding = " + System.getProperty("sun.stderr.encoding"));
        System.out.println("    native.encoding = " + System.getProperty("native.encoding"));
    }
}
```

```
sun.stdout.encoding = null
sun.stderr.encoding = null
    native.encoding = GBK
```

## Patching!

首先我尝试了在 `build.gradle` 中添加了以下内容

```groovy
tasks.withType(JavaExec) { JavaExec task ->
    task.doFirst { println "Hi" }
}
```

然后运行, 居然看到了不在主程序里的 `Hi`!

这说明 IDEA 运行 Java 程序是通过动态创建一个 `JavaExec` 任务来启动一个程序的

然后将代码改成

```groovy
tasks.withType(JavaExec) { JavaExec task ->
    task.jvmArgs += ['-Dsun.stdout.encoding=utf8']
    task.jvmArgs += ['-Dsun.stderr.encoding=utf8']
}
```

再次运行, 中文成功显示!!!!!

## Final Patch!!!

但是总不能每个 Gradle 项目都加吧, 于是去搜索相关的资料, 找到 Gradle 支持全局的 `Initialization Scripts` 的

> https://docs.gradle.org/current/userguide/init_scripts.html

只需要在 `$GRADLE_USER_HOME/init.d` 创建一个新的 `Initialization Script` 即可

> 此处我创建了一个名为 `k-javaexec-out-as-utf8.init.gradle` 的 init script

> Tip: Using an init script (From Gradle)
> - Put a file called init.gradle (or init.gradle.kts for Kotlin) in the `USER_HOME/.gradle/` directory.
> - Put a file that ends with .gradle (or .init.gradle.kts for Kotlin) in the `USER_HOME/.gradle/init.d/` directory.
> - Put a file that ends with .gradle (or .init.gradle.kts for Kotlin) in the `GRADLE_HOME/init.d/` directory

然后写入

```groovy

allprojects {
    tasks.withType(JavaExec) { JavaExec task ->
        task.jvmArgs += ['-Dsun.stdout.encoding=utf8']
        task.jvmArgs += ['-Dsun.stderr.encoding=utf8']
    }
}

```

一切大功告成!

-------------------------------

## 附录 - 如何得出 Java18 main 是 Gradle 启动的

打开 `Process Explorer`, 找到主程序, 可以看到 `parent process` 是 `Gradle Daemon`
