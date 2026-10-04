using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace TurnTabler;

internal static class Artwork
{
    internal static (BitmapSource Body, BitmapSource Record, BitmapSource Highlights) Load()
    {
        var source = new BitmapImage();
        using var imageStream = BundledAssets.Open("Record.png");
        source.BeginInit();
        source.StreamSource = imageStream;
        source.CacheOption = BitmapCacheOption.OnLoad;
        source.EndInit();
        source.Freeze();
        var bitmap = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        int width = bitmap.PixelWidth, height = bitmap.PixelHeight, stride = width * 4;
        var pixels = new byte[stride * height]; bitmap.CopyPixels(pixels, stride, 0);
        var plinth = Geometry.Parse("M157,66 H1362 Q1469,66 1469,175 V850 Q1469,958 1364,958 H158 Q61,958 61,852 V172 Q61,66 157,66 Z");
        var inner = Geometry.Parse("M165,111 H1358 Q1429,111 1429,184 V845 Q1429,920 1358,920 H166 Q104,920 104,843 V187 Q104,111 165,111 Z");
        var hardware = Geometry.Parse("M1245,83 H1358 V190 H1245 Z M1280,179 A117,117 0 1 0 1280,413 A117,117 0 1 0 1280,179 M1098,665 L1182,701 1118,821 1010,772 Z");
        var tube = Geometry.Parse("M1293,172 L1287,466 C1295,602 1260,674 1117,738 M1340,332 L1427,421 M1109,771 L1157,818").GetWidenedPathGeometry(new Pen(Brushes.White, 35));
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        {
            int i = y * stride + x * 4;
            var point = new Point(x, y);
            bool instrument = x > 980 && (hardware.FillContains(point) || tube.FillContains(point));
            bool record = Math.Pow((x - 664) / 463.0, 2) + Math.Pow((y - 487) / 444.0, 2) < 1;
            if ((record || !plinth.FillContains(point)) && !instrument) { pixels[i + 3] = 0; continue; }
            double value = Math.Max(pixels[i], Math.Max(pixels[i + 1], pixels[i + 2]));
            double alpha;
            if (instrument) alpha = Math.Clamp((value - 5) / 24, 0, 1);
            else
            {
                alpha = Math.Max(0, (value - 3) / 252);
                if (alpha > 0) for (int c = 0; c < 3; c++) pixels[i + c] = (byte)Math.Min(255, pixels[i + c] / alpha);
                if (inner.FillContains(point)) alpha *= .32;
            }
            pixels[i + 3] = (byte)Math.Round(alpha * 255);
        }
        var body = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, stride); body.Freeze();
        var crop = new CroppedBitmap(source, new Int32Rect(201, 43, 926, 888));
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.PushClip(new EllipseGeometry(new Point(270, 270), 270, 270));
            dc.DrawImage(crop, new Rect(0, 0, 540, 540));
            // Mirror unobstructed grooves into the sector beneath the stationary pickup.
            var wedge = Geometry.Parse("M270,270 L646,407 A400,400 0 0 1 487,606 Z");
            dc.PushClip(wedge); dc.PushTransform(new RotateTransform(180, 270, 270));
            dc.DrawImage(crop, new Rect(0, 0, 540, 540)); dc.Pop(); dc.Pop(); dc.Pop();
        }
        var rotor = new RenderTargetBitmap(540, 540, 96, 96, PixelFormats.Pbgra32); rotor.Render(visual); rotor.Freeze();
        var straight = new FormatConvertedBitmap(rotor, PixelFormats.Bgra32, null, 0);
        var highlights = new byte[540 * 540 * 4]; straight.CopyPixels(highlights, 540 * 4, 0);
        for (int y = 0; y < 540; y++) for (int x = 0; x < 540; x++)
        {
            int i = (y * 540 + x) * 4;
            double radius = Math.Sqrt(Math.Pow(x - 270, 2) + Math.Pow(y - 270, 2));
            double value = (highlights[i] + highlights[i + 1] + highlights[i + 2]) / 3.0;
            byte alpha = highlights[i + 3];
            highlights[i] = 231; highlights[i + 1] = 224; highlights[i + 2] = 211;
            highlights[i + 3] = (byte)(alpha == 0 || radius < 99 ? 0 : Math.Clamp((value - 13) * .85, 0, 115));
        }
        var sheen = BitmapSource.Create(540, 540, 96, 96, PixelFormats.Bgra32, null, highlights, 540 * 4); sheen.Freeze();
        return (body, rotor, sheen);
    }
}
