---
title: JVM 权限逃逸技术
categories: [jvm]
tags: [jvm, root, jdk9]
---

*前言: 仅研究 JDK 9+, JDK 8- 无研究意义*


从 `Java 9` 开始, Java 引入了一个新的概念, `模块(Module)`. 模块的存在, 限制了反射技术, 在 `JDK 16` 中, 直接反射越权修改 `java.base` 甚至会得到错误 `java.lang.reflect.InaccessibleObjectException`, 对于某些需要的 devops 而言意味着无法完成预期操作

---

在阅读 `java.lang.reflect.AccessibleObject` 源码后, 有如下代码片段

```java

   /**
    * If the given AccessibleObject is a {@code Constructor}, {@code Method}
    * or {@code Field} then checks that its declaring class is in a package
    * that can be accessed by the given caller of setAccessible.
    */
    void checkCanSetAccessible(Class<?> caller) {
        // do nothing, needs to be overridden by Constructor, Method, Field
    }

    final void checkCanSetAccessible(Class<?> caller, Class<?> declaringClass) {
        checkCanSetAccessible(caller, declaringClass, true);
    }

    private boolean checkCanSetAccessible(Class<?> caller,
                                          Class<?> declaringClass,
                                          boolean throwExceptionIfDenied) {
        if (caller == MethodHandle.class) {
            throw new IllegalCallerException();   // should not happen
        }

        Module callerModule = caller.getModule();
        Module declaringModule = declaringClass.getModule();

        if (callerModule == declaringModule) return true;
        if (callerModule == Object.class.getModule()) return true;
        if (!declaringModule.isNamed()) return true;

        String pn = declaringClass.getPackageName();
        int modifiers;
        if (this instanceof Executable) {
            modifiers = ((Executable) this).getModifiers();
        } else {
            modifiers = ((Field) this).getModifiers();
        }

        // class is public and package is exported to caller
        boolean isClassPublic = Modifier.isPublic(declaringClass.getModifiers());
        if (isClassPublic && declaringModule.isExported(pn, callerModule)) {
            // member is public
            if (Modifier.isPublic(modifiers)) {
                logIfExportedForIllegalAccess(caller, declaringClass);
                return true;
            }

            // member is protected-static
            if (Modifier.isProtected(modifiers)
                && Modifier.isStatic(modifiers)
                && isSubclassOf(caller, declaringClass)) {
                logIfExportedForIllegalAccess(caller, declaringClass);
                return true;
            }
        }

        // package is open to caller
        if (declaringModule.isOpen(pn, callerModule)) {
            logIfOpenedForIllegalAccess(caller, declaringClass);
            return true;
        }

        if (throwExceptionIfDenied) {
            // not accessible
            String msg = "Unable to make ";
            if (this instanceof Field)
                msg += "field ";
            msg += this + " accessible: " + declaringModule + " does not \"";
            if (isClassPublic && Modifier.isPublic(modifiers))
                msg += "exports";
            else
                msg += "opens";
            msg += " " + pn + "\" to " + callerModule;
            InaccessibleObjectException e = new InaccessibleObjectException(msg);
            if (printStackTraceWhenAccessFails()) {
                e.printStackTrace(System.err);
            }
            throw e;
        }
        return false;
    }

```

有两个关键判断逻辑: `declaringModule.isExported(pn, callerModule)`, `declaringModule.isOpen(pn, callerModule)`

阅读 `Module.java` 后发现有 `implAddExports` 方法, 通过 `IDEA` 查找调用引用发现了 `java.lang.System` 有访问此方法的 `JDK Internal API`

```java

    private static void setJavaLangAccess() {
        // Allow privileged classes outside of java.lang
        SharedSecrets.setJavaLangAccess(new JavaLangAccess() {
            public Module defineModule(ClassLoader loader,
                                       ModuleDescriptor descriptor,
                                       URI uri) {
                return new Module(null, loader, descriptor, uri);
            }
            public Module defineUnnamedModule(ClassLoader loader) {
                return new Module(loader);
            }
            public void addReads(Module m1, Module m2) {
                m1.implAddReads(m2);
            }
            public void addReadsAllUnnamed(Module m) {
                m.implAddReadsAllUnnamed();
            }
            public void addExports(Module m, String pn, Module other) {
                m.implAddExports(pn, other);
            }
            public void addExportsToAllUnnamed(Module m, String pn) {
                m.implAddExportsToAllUnnamed(pn);
            }
            public void addOpens(Module m, String pn, Module other) {
                m.implAddOpens(pn, other);
            }
            public void addOpensToAllUnnamed(Module m, String pn) {
                m.implAddOpensToAllUnnamed(pn);
            }
            public void addOpensToAllUnnamed(Module m, Set<String> concealedPackages, Set<String> exportedPackages) {
                m.implAddOpensToAllUnnamed(concealedPackages, exportedPackages);
            }
            public void addUses(Module m, Class<?> service) {
                m.implAddUses(service);
            }
        });
    }
```

找到了 JDK 提供的后门之后, 我们只需要调用 `SharedSecrets.getJavaLangAccess().addExports` 就能开后门了....
不对，目前还无法调用 `SharedSecrets`, 还需要一些手段....

在 `java.lang.reflect` 中翻到了一个特别的东西, `java.lang.reflect.Proxy`, 她是破局的关键中心

抱着好奇的心里, 我尝试了使用 `Proxy` 实现 `jdk.internal.access` 中的一个接口玩玩

```java
    public static void main(String[] args) throws Exception {
        var obj = Proxy.newProxyInstance(
                Usffsa.class.getClassLoader(),
                new Class[]{Class.forName("jdk.internal.access.JavaLangAccess")},
                new InvocationHandler() {
                    @Override
                    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
                        return null;
                    }
                }
        );
        System.out.println(obj);
    }
```

没想到, 运行成功了(eg: 没有对应权限(`Exported`)是不能实现对应接口的), 迎接着激动的心情, 输出了更多的详细信息

```java
        System.out.println(obj);
        System.out.println(obj.getClass());
        System.out.println(obj.getClass().getModule());
        System.out.println(Object.class.getModule().isExported("jdk.internal.access", obj.getClass().getModule()));
```

```
null
class com.sun.proxy.jdk.proxy1.$Proxy0
module jdk.proxy1
true
```

破局点找到了, `java.lang.reflect.Proxy` 拥有打开模块访问的权利, 然后尝试对该模块进行注入

```java
    public static void main(String[] args) throws Exception {
        var ccl = new ClassLoader(Usffsa.class.getClassLoader()) {
            Class<?> defineClass(byte[] code) {
                return defineClass(null, code, 0, code.length);
            }
        };
        var obj = Proxy.newProxyInstance(
                ccl,
                new Class[]{Class.forName("jdk.internal.access.JavaLangAccess")},
                (proxy, method, args1) -> null
        );
        var writer = new ClassWriter(0); // org.objectweb.asm.ClassWriter
        writer.visit(Opcodes.V1_8, 0,
                obj.getClass().getPackageName().replace('.', '/') + "/Test0",
                null,
                "java/lang/Object",
                null
        );
        var injectedClass = ccl.defineClass(writer.toByteArray());
        System.out.println("Proxy     Module  : " + obj.getClass().getModule());
        System.out.println("Injected  Module  : " + injectedClass.getModule());
        System.out.println("Is Same Module    : " + (injectedClass.getModule() == obj.getClass().getModule()));
    }
```
```
Proxy     Module  : module jdk.proxy1
Injected  Module  : module jdk.proxy1
Is Same Module    : true
```

至此已经破开了 JVM 的模块限制的死局, 实际应用可参考 [\[Karlatemp/UnsafeAccessor\]](https://github.com/Karlatemp/UnsafeAccessor)
