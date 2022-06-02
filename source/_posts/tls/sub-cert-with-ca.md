---
title: 使用自定义 CA 生成 HTTPS 证书
date: 2022-06-02 00:00:01
categates: [TLS]
description: Raw JavaCode
---

```java
package io.github.karlatemp.jmse.kit;

import org.bouncycastle.asn1.*;
import org.bouncycastle.asn1.x509.*;
import org.bouncycastle.jce.X509Principal;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;
import org.bouncycastle.x509.X509V3CertificateGenerator;

import java.io.File;
import java.io.FileInputStream;
import java.math.BigInteger;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.KeyFactory;
import java.security.KeyPairGenerator;
import java.security.Security;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Date;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.concurrent.TimeUnit;
import java.util.random.RandomGenerator;

@SuppressWarnings("resource")
public class SubKeyCreation {
    public static void main(String[] args) throws Throwable {
        var webname = "localhost";
        var outDir = new File("B:/ootx").toPath();
        var provider = new BouncyCastleProvider();
        Security.addProvider(provider);
        var caRootFile = new File("Karlatemp.ssl.crt");
        var caRootCert = (X509Certificate) CertificateFactory.getInstance("X.509", provider)
                .generateCertificate(new FileInputStream(caRootFile));
        System.out.println(caRootCert);
        var caRootPwd = KeyFactory.getInstance("RSA", provider)
                .generatePrivate(new PKCS8EncodedKeySpec(
                        new FileInputStream("Karlatemp.ssl.private.pem").readAllBytes()
                ));
        System.out.println(caRootPwd);


        X509V3CertificateGenerator generator = new X509V3CertificateGenerator();
        generator.setIssuerDN(caRootCert.getSubjectX500Principal());
        {
            var num = new StringBuilder();
            var rand = RandomGenerator.getDefault();
            while (num.length() < 32) {
                num.append(Integer.toHexString(rand.nextInt() & 0xF));
            }
            generator.setSerialNumber(new BigInteger(num.toString(), 16));
        }
        {
            var mp = new HashMap<>();
            mp.put(X509Name.C, "AU");
            mp.put(X509Name.ST, "Some-State");
            mp.put(X509Name.O, "Internet SK ROX Ltd");
            mp.put(X509Name.CN, "localhost");
            mp.put(X509Name.E, "noreply@noreply.github.com");

            generator.setSubjectDN(new X509Principal(
                    new Hashtable<>(mp)
            ));
        }
        var generateKeyPair = KeyPairGenerator.getInstance("RSA", provider).generateKeyPair();
        {
            // System.out.println(kp);
            generator.setPublicKey(generateKeyPair.getPublic());
            generator.setSignatureAlgorithm("SHA256withRSA");
        }
        var now = System.currentTimeMillis();
        generator.setNotBefore(new Date(now - TimeUnit.DAYS.toMillis(3)));
        generator.setNotAfter(new Date(now + TimeUnit.DAYS.toMillis(365 * 5)));

        {
            generator.addExtension(Extension.keyUsage, false, new KeyUsage(
                    KeyUsage.digitalSignature | KeyUsage.nonRepudiation | KeyUsage.keyEncipherment
            ));
            generator.addExtension(Extension.extendedKeyUsage, false, ExtendedKeyUsage.getInstance(
                    new DERSequence(new ASN1Encodable[]{
                            KeyPurposeId.id_kp_serverAuth,
                            KeyPurposeId.id_kp_clientAuth,
                            KeyPurposeId.id_kp_codeSigning,
                            KeyPurposeId.id_kp_emailProtection,
                            KeyPurposeId.id_kp_timeStamping,
                    })
            ));
            generator.addExtension(Extension.subjectAlternativeName, false, new DERSequence(
                    new ASN1Encodable[]{
                            // IPv4
                            new DERTaggedObject(false, BERTags.CONTEXT_SPECIFIC, 7, new DEROctetString(
                                    InetAddress.getByName("192.168.1.103").getAddress()
                            )),
                            // DNS Name
                            new DERTaggedObject(false, BERTags.CONTEXT_SPECIFIC, 2, new DEROctetString(
                                    webname.getBytes(StandardCharsets.UTF_8)
                            )),
                    }
            ));
        }
        var out = generator.generate(caRootPwd);
        System.out.println(out);

        {
            Files.createDirectories(outDir);
            Files.write(outDir.resolve(webname + ".der"), out.getEncoded());
            Files.write(outDir.resolve(webname + ".pubkey"), generateKeyPair.getPublic().getEncoded());
            Files.write(outDir.resolve(webname + ".key"), generateKeyPair.getPrivate().getEncoded());
            try (var writer = new PemWriter(
                    Files.newBufferedWriter(outDir.resolve(webname + ".crt"))
            )) {
                writer.writeObject(new PemObject("CERTIFICATE", out.getEncoded()));
            }
            try (var writer = new PemWriter(
                    Files.newBufferedWriter(outDir.resolve(webname + ".crt.key"))
            )) {
                writer.writeObject(new PemObject("PRIVATE KEY", generateKeyPair.getPrivate().getEncoded()));
            }
        }
    }
}

```
