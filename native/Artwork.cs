using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace TurnTabler;

internal static class Artwork
{
    internal static int Export(string directory)
    {
        Directory.CreateDirectory(directory);
        var layers = Load();
        foreach (var item in new[] { ("body", layers.Body), ("record", layers.Record), ("highlights", layers.Highlights), ("tonearm", layers.Tonearm) })
        {
            var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(item.Item2));
            using var output = File.Create(Path.Combine(directory, item.Item1 + ".png")); png.Save(output);
        }
        return 0;
    }
    internal static (BitmapSource Body, BitmapSource Record, BitmapSource Highlights, BitmapSource Tonearm) Load()
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
        var armPixels = new byte[pixels.Length];
        var plinth = Geometry.Parse("M157,66 H1362 Q1469,66 1469,175 V850 Q1469,958 1364,958 H158 Q61,958 61,852 V172 Q61,66 157,66 Z");
        var inner = Geometry.Parse("M165,111 H1358 Q1429,111 1429,184 V845 Q1429,920 1358,920 H166 Q104,920 104,843 V187 Q104,111 165,111 Z");
        var hardware = Geometry.Parse("M1245,83 H1358 V190 H1245 Z M1280,179 A117,117 0 1 0 1280,413 A117,117 0 1 0 1280,179 M1098,665 L1182,701 1118,821 1010,772 Z");
        var tube = Geometry.Parse("M1293,172 L1287,466 C1295,602 1260,674 1117,738 M1340,332 L1427,421 M1109,771 L1157,818").GetWidenedPathGeometry(new Pen(Brushes.White, 35));
        var movingTube = Geometry.Parse("M1287,351 L1287,466 C1295,602 1260,674 1117,738 M1109,771 L1157,818").GetWidenedPathGeometry(new Pen(Brushes.White, 35));
        var cartridge = Geometry.Parse("M1098,665 L1182,701 1118,821 1010,772 Z");
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
            if (instrument && y >= 351 && (movingTube.FillContains(point) || cartridge.FillContains(point)))
            {
                Array.Copy(pixels, i, armPixels, i, 4);
                pixels[i + 3] = 0;
            }
        }
        var body = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, stride); body.Freeze();
        var crop = new CroppedBitmap(source, new Int32Rect(201, 43, 926, 888));
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.PushClip(new EllipseGeometry(new Point(270, 270), 270, 270));
            dc.DrawImage(crop, new Rect(0, 0, 540, 540));
            dc.Pop();
        }
        var rotor = new RenderTargetBitmap(540, 540, 96, 96, PixelFormats.Pbgra32); rotor.Render(visual); rotor.Freeze();
        var straight = new FormatConvertedBitmap(rotor, PixelFormats.Bgra32, null, 0);
        var highlights = new byte[540 * 540 * 4]; straight.CopyPixels(highlights, 540 * 4, 0);
        // Replace the pickup's photographed footprint with opposite-side grooves.
        // Feather the sector edges so the repair does not leave a rotating fan-shaped seam.
        var unpatched = (byte[])highlights.Clone();
        static double Smooth(double value) { value = Math.Clamp(value, 0, 1); return value * value * (3 - 2 * value); }
        for (int y = 0; y < 540; y++) for (int x = 0; x < 540; x++)
        {
            double angle = Math.Atan2(y - 269.5, x - 269.5) * 180 / Math.PI;
            double radius = Math.Sqrt(Math.Pow(x - 269.5, 2) + Math.Pow(y - 269.5, 2));
            double blend = Smooth((angle - 18) / 14) * Smooth((70 - angle) / 14) * Smooth((radius - 228) / 20);
            if (blend <= 0) continue;
            int destination = (y * 540 + x) * 4, opposite = ((539 - y) * 540 + 539 - x) * 4;
            for (int channel = 0; channel < 3; channel++)
                highlights[destination + channel] = (byte)Math.Round(unpatched[destination + channel] * (1 - blend) + unpatched[opposite + channel] * blend);
        }
        var surfacePixels = (byte[])highlights.Clone();
        // Separate the photograph's broad studio lighting from its fine groove texture.
        // The grooves turn with the disc; the light source stays in the room.
        const int integralStride = 541;
        var lightSum = new double[integralStride * integralStride];
        var lightWeight = new int[lightSum.Length];
        for (int y = 0; y < 540; y++) for (int x = 0; x < 540; x++)
        {
            int i = (y * 540 + x) * 4, k = (y + 1) * integralStride + x + 1;
            int valid = highlights[i + 3] > 0 ? 1 : 0;
            double luminance = (highlights[i] + highlights[i + 1] + highlights[i + 2]) / 3.0;
            lightSum[k] = luminance * valid + lightSum[k - 1] + lightSum[k - integralStride] - lightSum[k - integralStride - 1];
            lightWeight[k] = valid + lightWeight[k - 1] + lightWeight[k - integralStride] - lightWeight[k - integralStride - 1];
        }
        for (int y = 0; y < 540; y++) for (int x = 0; x < 540; x++)
        {
            int i = (y * 540 + x) * 4;
            double radius = Math.Sqrt(Math.Pow(x - 270, 2) + Math.Pow(y - 270, 2));
            double value = (highlights[i] + highlights[i + 1] + highlights[i + 2]) / 3.0;
            byte alpha = highlights[i + 3];
            int left = Math.Max(0, x - 22), right = Math.Min(540, x + 23);
            int top = Math.Max(0, y - 22), bottom = Math.Min(540, y + 23);
            int a = top * integralStride + left, b = top * integralStride + right;
            int c = bottom * integralStride + left, d = bottom * integralStride + right;
            double broadLight = (lightSum[d] - lightSum[b] - lightSum[c] + lightSum[a]) /
                Math.Max(1, lightWeight[d] - lightWeight[b] - lightWeight[c] + lightWeight[a]);
            double grooveBlend = Math.Clamp((radius - 100) / 15, 0, 1) * Math.Clamp((269 - radius) / 3, 0, 1);
            double grooveValue = Math.Clamp(18 + (value - broadLight) * .65, 8, 58);
            for (int channel = 0; channel < 3; channel++)
                surfacePixels[i + channel] = (byte)Math.Round(surfacePixels[i + channel] * (1 - grooveBlend) + grooveValue * grooveBlend);
            double edgeFade = Math.Clamp((radius - 100) / 20, 0, 1) * Math.Clamp((269 - radius) / 10, 0, 1);
            highlights[i] = highlights[i + 1] = highlights[i + 2] = 235;
            highlights[i + 3] = (byte)(alpha == 0 ? 0 : Math.Clamp((broadLight - 14) * .35, 0, 44) * edgeFade);
        }
        var surface = BitmapSource.Create(540, 540, 96, 96, PixelFormats.Bgra32, null, surfacePixels, 540 * 4); surface.Freeze();
        var sheen = BitmapSource.Create(540, 540, 96, 96, PixelFormats.Bgra32, null, highlights, 540 * 4); sheen.Freeze();
        var arm = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, armPixels, stride); arm.Freeze();
        return (body, surface, sheen, arm);
    }
}
