using System;
using System.Drawing;
using System.Windows.Forms;

public static class GeneralRuntimeProbe {
    [STAThread]
    public static int Main() {
        int status = 1;
        try {
            Application.EnableVisualStyles();
            using (Form form = new Form()) {
                form.Text = "ExeRunner general .NET test";
                form.ClientSize = new Size(360, 140);
                Label label = new Label();
                label.Text = "Windows Forms / Unicode: Проба";
                label.Dock = DockStyle.Fill;
                label.TextAlign = ContentAlignment.MiddleCenter;
                form.Controls.Add(label);
                Timer timer = new Timer();
                timer.Interval = 350;
                timer.Tick += delegate {
                    timer.Stop();
                    try {
                        using (Bitmap bitmap = new Bitmap(360, 140)) {
                            form.DrawToBitmap(bitmap, new Rectangle(0, 0, 360, 140));
                            if (!form.IsHandleCreated || label.Text.IndexOf("Проба") < 0) throw new Exception("WinForms controls not initialized");
                            Console.WriteLine("PASS WinForms window and drawing");
                            Console.WriteLine("PASS Managed Unicode text");
                            Console.WriteLine("ARCH " + (IntPtr.Size * 8));
                            Console.WriteLine("RESULT PASS");
                            status = 0;
                        }
                    } catch (Exception e) { Console.WriteLine("FAIL " + e.GetType().Name + ": " + e.Message); }
                    form.Close();
                };
                form.Shown += delegate { timer.Start(); };
                Application.Run(form);
                timer.Dispose();
            }
        } catch (Exception e) { Console.WriteLine("FAIL " + e.GetType().Name + ": " + e.Message); }
        return status;
    }
}
