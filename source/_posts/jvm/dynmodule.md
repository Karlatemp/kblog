---
title: "Java 动态模块系统 | Java dynamic module system"
categories: [jvm]
tags: [jvm, jdk9]
---

## 前言

在使用高版本的时候, 总会不可避免的接触到模块系统, 比如反射操作 `java.base` 已经十分困难. 既然 JDK 内部可以享受到模块的保护, 那么我们自己的代码是否也可以享受到模块系统的保护呢

当然可以，而且也不是非常麻烦。

使用模块，你将面对以下问题

- <span style="color: green">得到反射保护, 外部代码将不能通过反射强行修改/调用私有成员</span>
- <span style="color: red">更严格的访问控制, 不能直接访问非 required 的模块</span>
- <span style="color: red">失去 `--add-opens=....=ALL-UNNAMED` 的归属判断</span>
- <span style="color: gray">需要专门的 ClassLoader / 需要自行实现 ClassLoader</span>

使用模块的适用情况

- 需要编写严格的附属(插件)系统
- 需要保护自身代码/保护自身内存空间
- ~~觉得弄着好玩~~

## 定义一个模块

> 注: 此处的定义指的是, 通过运行时代码在运行时定义一个模块.
> 而不是大多数资料说的直接写一个 `module-info.java`

要定义一个模块, 首先需要一个模块的描述符文件 (`ModuleDescriptor`), 可以从以编码文件读取 (`ModuleDescriptor.read(InputStream) <- module-info.class`), 也可以在运行时动态生成一个(`ModuleDescriptor.newModule("name_of_module").build()`)

jvm 通过包来区分模块, 而一个模块的全部包都需要提前指定, jvm 才会为这些包分配到一个模块内

```java
var moduleDescriptor = ModuleDescriptor.newModule("my.custom_module")
    .packages(Set.of("io.github.karlatemp.jmse.main"))
    .exports("io.github.karlatemp.jmse.main")
    .build();
```

这里我们已经拥有了一个模块的描述符, 现在我们还需要一个模块描述的引用, 以及一个模块查找器以让 jvm 可以找到我们的模块

```java
var myModuleReference = new ModuleReference(
    moduleDescriptor, null
) {
    @Override public ModuleReader open() throws IOException {
        throw new UnsupportedOperationException();
    }
}
var myModuleFinder = new ModuleFinder() {
    @Override
    public Optional<ModuleReference> find(String name) {
        if (name.equals(moduleDescriptor.name())) {
            return Optional.of(myModuleReference);
        }
        return Optional.empty();
    }

    @Override
    public Set<ModuleReference> findAll() {
        return Set.of(myModuleReference);
     }
};
```

最后，定义一个模块
```java
var bootLayer = ModuleLayer.boot();
var myConfiguration = bootLayer.configuration().resolve(
    myModuleFinder, ModuleFinder.of(), Set.of(moduleDescriptor.name())
);
var classLoader = ClassLoader.getSystemClassLoader();
var controller = ModuleLayer.defineModules(
    myConfiguration, List.of(bootLayer), $ -> classLoader
);

Class.forName("io.github.karlatemp.jmse.main.ModuleMain", false, classLoader)
    .getMethod("launch")
    .invoke(null);
```

## ServiceLoader / Class.forName(Module, String)

还记得 `需要专门的 ClassLoader / 需要自行实现 ClassLoader` 吗, 虽然在上文已经成功定义了一个模块，但是只要使用 `ServiceLoader` / `Class.forName(Module, String)`, 那么将无法找到对应的类, 因为一般的 ClassLoader 并没有专门处理动态加载的模块

### Analyze

通过进行调用分析, 最终可以发现以上两个东西最终都进入到了下面的方法

```java
public class ClassLoader {
    final Class<?> loadClass(Module module, String name) {
        synchronized (getClassLoadingLock(name)) {
            // First, check if the class has already been loaded
            Class<?> c = findLoadedClass(name);
            if (c == null) {
                c = findClass(module.getName(), name);
            }
            if (c != null && c.getModule() == module) {
                return c;
            } else {
                return null;
            }
        }
    }
    protected Class<?> findClass(String moduleName, String name) {
        if (moduleName == null) {
            try {
                return findClass(name);
            } catch (ClassNotFoundException ignore) { }
        }
        return null;
    }
}
```

不难发现, 由于默认没有处理模块, 导致指定搜索模块的时候将搜索不到动态定义的模块

而 `jdk.internal.loader.ClassLoader$AppClassLoader` 并没有处理通过 `ModuleLayer.defineModule` 定义的模块, 于是也不能直接将模块定义到系统类加载器

### 自行实现类加载器

自行实现类加载器十分简单，只需要

```java
public class MyCustomClassLoader extends URLClassLoader {
    String moduleName;

    @Override
    protected Class<?> findClass(String moduleName, String name) {
        // System.out.println("Find class: " + moduleName + "/" + name);
        if (this.moduleName.equals(moduleName)) {
            try {
                return findClass(name);
            } catch (ClassNotFoundException ignored) {
            }
        }
        return super.findClass(moduleName, name);
    }
}
```

### 使用 JDK 内置的类加载器

只需要实现 `ModuleReference.open(): ModuleReader`, 然后使用

```java
var controller = ModuleLayer.defineModulesWithOneLoader(
        myConfiguration,
        List.of(bootLayer),
        ClassLoader.getSystemClassLoader().getParent()
);
var classLoader = controller.layer().findLoader(moduleDescriptor.name());
```

即可使用 JDK 内置的内加载器

-----

## 完整参考

- [java-module-system-explore](https://github.com/Karlatemp/java-module-system-explore)
  - [BootModuleByStandard.java](https://github.com/Karlatemp/java-module-system-explore/blob/master/src/main/java/io/github/karlatemp/jmse/boot/BootModuleByStandard.java)
  - [MyCustomClassLoader.java](https://github.com/Karlatemp/java-module-system-explore/blob/master/src/main/java/io/github/karlatemp/jmse/boot/MyCustomClassLoader.java)