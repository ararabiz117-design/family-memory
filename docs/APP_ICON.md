# 「家族の記憶」アプリアイコン

更新日: 2026-09-11

## 正本

- 元画像: `assets/branding/app_icon_v1.png`
- Android / iOS / Web用アイコンは `flutter_launcher_icons` で生成する
- iOS版は生成時にalpha channelを除去する

## デザイン意図

家族のつながり、記憶の継承、安心感を、3つのハート状の葉と一本の木で表した。淡いピンク、コーラル、ミント、クリームをアプリ本体のUIと揃え、小さな表示でも判別できる太いシルエットにしている。

文字、人物の顔、墓石、宗教記号は使わない。

## 再生成コマンド

```powershell
flutter pub get
dart run flutter_launcher_icons
```

