# CineMatch Blog Paneli Kurulumu

Blog paneli `public/admin-blog.html` adresindedir. Panel, CineMatch Firebase Auth
hesabını kullanır; bağımsız bir kullanıcı sistemi oluşturmaz.

## Firebase kurulumu

1. Sağlanan mevcut Firestore kuralları blog izinleriyle birleştirilerek
   `firestore.rules` dosyasına alındı ve `firebase.json` bu dosyaya bağlandı.
2. Sağlanan mevcut Storage kuralları blog görsel izinleriyle birleştirilerek
   `storage.rules` dosyasına alındı ve `firebase.json` bu dosyaya bağlandı.
3. Functions, Hosting ve güncellenen kuralları kendi yayın akışınızla deploy
   edin. `TMDB_ACCESS_TOKEN` secret'ı mevcut sosyal/TMDB fonksiyonlarıyla aynı
   secret'tır.

## Blogger yetkisi

Sabit admin UID'leri ve `users/{uid}.role == "admin"` olan hesaplar blog
yöneticisidir. Yönetici blog panelindeki **Blogger Yetkileri** bölümünden
uygulama kullanıcılarını arayıp yetkilendirebilir.

Yetki belgesi:

```text
blog_editors/{uid}
  active: true | false
  updatedAt: Timestamp
  updatedBy: adminUid
```

## Veri koleksiyonları

- `blog_posts`: taslak, yayın ve arşiv durumları dahil özel editör kaydı.
- `public_blog_posts`: yalnızca yayındaki yazıların uygulamanın okuyacağı
  güvenli kopyası.
- `blog_editors`: blogger erişim listesi.
- `blog_images/{uploaderUid}/{postId}/...`: Firebase Storage görselleri.

Yayınlanan belgelerde başlık, özet, güvenli HTML, düz metin, yazar kullanıcı
adı/profil bilgisi, okuma süresi, kapak, görseller ve TMDB film kimlikleri hazır
olarak tutulur. Mobil uygulama entegrasyonu `public_blog_posts` üzerinden
yapılabilir.

## Web sitesi

- `blog.html`: yayınlanan yazıların aranabilir ve kategori filtreli listesi.
- `blog-detail.html?id={postId}`: zengin içerik, yazar ve TMDB film etiketleri.
- `index.html`: son üç yayınlanmış yazıyı otomatik gösterir.

Bu sayfalar yalnızca `public_blog_posts` koleksiyonunu okur. Gerekli public
okuma kuralı birleşik `firestore.rules` dosyasına eklenmiştir.
