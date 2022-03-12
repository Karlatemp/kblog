---
title: 使用 jdk.foreign 访问本机代码
tags: [jvm, jdk.foreign]
categories: [jvm]
date: 2022-3-12 20:54:00
---

{% note blue %}

`jdk.foreign` 与 `JDK 16` 开始可用, 并处于<span style="color:red">**测试**</span>状态.

代码在
`Windows 10 Enterprise; 1909 (OS Build 18363.1679)`
`openjdk 17 2021-09-14; 64-Bit Server VM (build 17+35-2724, mixed mode, sharing)`
下测试通过

{% endnote %}

## Environment prepare

开始一切之前, 需要准备好所有的一切东西

- Java IDE
- JDK 16+
- C/CPP IDE (Optional)

### Project initiation

首先，新建文件夹, ~~然后点击 Win, 点击关机~~, 使用 Java IDE 打开该文件夹.

创建以下文件

```properties 
## gradle/wrapper/gradle-wrapper.properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-7.3.3-all.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

```groovy
// settings.gradle
// <Empty file>
```

```groovy
// build.gradle
plugins {
    id 'java'
    id 'java-plugin'
}
repositories {
    mavenCentral()
}
dependencies {}
compileJava {
    options.compilerArgs += ['--add-modules', 'ALL-SYSTEM']
}
```

```java
// src/main/java/pkg/Boot.java
package pkg;
public class Boot {
    public static void main(String[] $$$$$$$$$$$$$$$$) throws Throwable {
    }
}
```

进入 `Project Structure > Project` 将 `Project SDK` 切换至 `JDK 16+`
右键 `build.gradle` 导入 gradle 项目, 等待导入完成后
右键 `pkg.Boot` 的入口点, 添加 jvm 参数 `--add-modules ALL-SYSTEM --enable-native-access ALL-UNNAMED`


## Code

根据 [JEP 419: Foreign Function & Memory API](https://openjdk.java.net/jeps/419) 的 Example, 可以很快写出看上去可以运行的代码.
使用 `jdk.foreign` 调用本机代码的步骤共三步, `本机方法寻址`, `方法签名拼接`, `执行`.

### Setup

第一步需要先获得相关的 api 对象, 以供我们完成桥接.

```java
var linker = CLinker.getInstance();
var symbolLookup = SymbolLookup.loaderLookup();
var systemLookup = CLinker.systemLookup();
```

### Native function symbol lookup

需要先拿到方法地址 (指针), 才能执行本机方法, JDK 提供了搜索方法符号的 api.

{% note yellow %}
寻址时需要的是实际名字, 而不是在 `****.h` 中使用 `#define` 定义的别名 (比如 `SetWindowLong` 实际应该为 `SetWindowLongA`)
{% endnote %}

```java
var system =
        systemLookup.lookup("system")
        .or(() -> symbolLookup.lookup("system"))
        .orElseThrow();
System.out.println(system);
```

### Function description mapping.

只有正确告诉 JVM 我们要执行的方法的签名是什么样的, JVM 才能正确处理相关的访问, 否则 `JVM Crashed`.

{% note blue %}
如无必要，切勿直接使用 MemoryLayout 中的定义
{% endnote %}

```java
// _DCRTIMP int __cdecl system(_In_opt_z_ char const* _Command)
var funcDesc = FunctionDescriptor.of(
    /* return */ CLinker.C_INT,
    /* argv...*/ CLinker.C_POINTER
);
var mh = linker.downcallHandle(
    // Java 眼中的方法签名
    MethodType.methodType(
        int.class, MemoryAddress.class
    ),
    funcDesc
);
System.out.println(mh); // MethodHandle(Addressable, MemoryAddress)int
                        //              |              `- 方法参数 ( char const* _Command )
                        //              |- 此参数为本机方法指针
```

### Invoke native function

`system` 方法需要一个指针 (char*), 由于 jdk 不允许直接获得一个方法对象的指针, 所以需要将相关内容拷贝到堆外内存.

其中 `jdk.foreign` 提供了 `ResourceScope` 防止内存泄露.

```java
try (var scope = ResourceScope.newConfinedScope()) {
    var allocator = SegmentAllocator.ofScope(scope);
    var cmd_java = "whoami".getBytes(StandardCharsets.UTF_8); // 如果有中文, 可能不是 utf8
    var cmd_cnative = allocator.allocate(cmd_java.length + 1);
    cmd_cnative.copyFrom(MemorySegment.ofArray(cmd_java));
    MemoryAccess.setByAtOffset(cmd_cnative, cmd_java.length, (byte) 0 /* \x00 */);

    var $ = (int) mh.invokeExact((Addressable) system, cmd_cnative.address());
    System.out.println($);
}
```

### Full code

```java
package pkg;

import jdk.incubator.foreign.*;

import java.lang.invoke.MethodType;
import java.nio.charset.StandardCharsets;

public class Boot {
    public static void main(String[] args) throws Throwable {
        var linker = CLinker.getInstance();
        var symbolLookup = SymbolLookup.loaderLookup();
        var systemLookup = CLinker.systemLookup();
        var system = systemLookup
                .lookup("system")
                .or(() -> symbolLookup.lookup("system"))
                .orElseThrow();
        System.out.println(system);
        // _DCRTIMP int __cdecl system(_In_opt_z_ char const* _Command)
        var funcDesc = FunctionDescriptor.of(
                CLinker.C_INT,
                CLinker.C_POINTER
        );
        var mh = linker.downcallHandle(MethodType.methodType(
                int.class, MemoryAddress.class
        ), funcDesc);
        System.out.println(mh);
        try (var scope = ResourceScope.newConfinedScope()) {
            var allocator = SegmentAllocator.ofScope(scope);
            var cmd_java = "whoami".getBytes(StandardCharsets.UTF_8);
            var cmd_cnative = allocator.allocate(cmd_java.length + 1);
            cmd_cnative.copyFrom(MemorySegment.ofArray(cmd_java));
            MemoryAccess.setByteAtOffset(cmd_cnative, cmd_java.length, (byte) 0 /* \u0000 */);

            var $ = (int) mh.invokeExact((Addressable) system, cmd_cnative.address());
            System.out.println($);
        }
    }
}

```
