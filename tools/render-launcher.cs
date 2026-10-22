using System;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using HordesOfAzeroth.Launcher;

static class RenderLauncher
{
    [STAThread]
    static void Main(string[] args)
    {
        var app = new App();
        app.InitializeComponent();
        var window = new MainWindow();
        ((System.Windows.Controls.Image)window.FindName("Art")).Source = new BitmapImage(new Uri("pack://application:,,,/HoALauncher;component/art/background.jpg"));
        var state = typeof(MainWindow).GetNestedType("LauncherState", BindingFlags.NonPublic);
        typeof(MainWindow).GetMethod("SetState", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(window, new object[] { Enum.Parse(state, "Ready"), "Ready to play", "" });
        var root = (FrameworkElement)window.Content;
        foreach (int width in new[] { 1280, 960 })
        {
            int height = width == 1280 ? 720 : 568;
            root.Measure(new Size(width, height));
            root.Arrange(new Rect(0, 0, width, height));
            root.UpdateLayout();
            var image = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            image.Render(root);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using (var file = File.Create(Path.Combine(args[0], "launcher-" + width + ".png")))
                encoder.Save(file);
        }
        app.Shutdown();
    }
}
