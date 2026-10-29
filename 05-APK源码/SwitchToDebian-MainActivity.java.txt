package com.raphael.switchtolinux;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.graphics.Color;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

public class MainActivity extends Activity {
    private TextView status;
    private TextView info;
    private Button btn;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private static final String FLAG = "/data/adb/to-linux";
    private static final String FLAG2 = "/sdcard/to-linux";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(56, 120, 56, 56);
        root.setBackgroundColor(Color.parseColor("#101418"));
        scroll.addView(root);

        TextView title = new TextView(this);
        title.setText("Raphael 双系统");
        title.setTextSize(28);
        title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView desc = new TextView(this);
        desc.setText("\n当前：Android 11 (MIUI)\n"
                + "另一个系统：Debian GNU/Linux 13\n\n"
                + "点按钮 → 写入 U-Boot 到 boot 分区并重启，\n"
                + "开机后进入 U-Boot 菜单，5 秒后自动启动 Debian。");
        desc.setTextSize(15);
        desc.setTextColor(Color.parseColor("#B0BEC5"));
        desc.setGravity(Gravity.CENTER);
        root.addView(desc);

        btn = new Button(this);
        btn.setText("切换到 Debian（会重启）");
        btn.setTextSize(20);
        btn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                confirm();
            }
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = 48;
        root.addView(btn, lp);

        status = new TextView(this);
        status.setTextSize(14);
        status.setTextColor(Color.parseColor("#80CBC4"));
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, 40, 0, 0);
        root.addView(status);

        info = new TextView(this);
        info.setTextSize(12);
        info.setTextColor(Color.parseColor("#607D8B"));
        info.setPadding(0, 48, 0, 0);
        root.addView(info);

        setContentView(scroll);
        refreshInfo();
    }

    private void confirm() {
        new AlertDialog.Builder(this)
                .setTitle("切换到 Debian？")
                .setMessage("手机将立即重启。\n\nAndroid 的数据不受影响，随时可以从 Debian 里用\n"
                        + "sudo switch-android 切回来。")
                .setPositiveButton("切换并重启", new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface d, int w) {
                        doSwitch();
                    }
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void doSwitch() {
        btn.setEnabled(false);
        btn.setText("正在切换…");
        status.setText("正在申请 root 权限…");
        new Thread(new Runnable() {
            public void run() {
                String out = sh("su", "-c",
                        "mkdir -p /data/adb; touch /data/adb/to-linux /sdcard/to-linux; "
                                + "chmod 644 /data/adb/to-linux; sync; "
                                + "ls -l /data/adb/to-linux; echo DONE");
                final boolean ok = new File(FLAG).exists() || new File(FLAG2).exists();
                ui.post(new Runnable() {
                    public void run() {
                        if (ok) {
                            status.setText("标记已创建，正在重启…");
                            status.setTextColor(Color.parseColor("#80CBC4"));
                        } else {
                            status.setText("失败（root 被拒？）\n" + out);
                            status.setTextColor(Color.parseColor("#EF5350"));
                            btn.setEnabled(true);
                            btn.setText("重试");
                        }
                    }
                });
                if (ok) {
                    sh("su", "-c", "sleep 1; svc power reboot || reboot");
                }
            }
        }).start();
    }

    private void refreshInfo() {
        new Thread(new Runnable() {
            public void run() {
                String imgs = sh("su", "-c",
                        "ls -l /data/raphael/u-boot.img /data/raphael/dtbo.img 2>&1; "
                                + "md5sum /data/raphael/u-boot.img 2>&1");
                String log = sh("su", "-c", "tail -4 /data/raphael/switch.log 2>&1");
                final String text = "===== 触发文件 =====\n"
                        + FLAG + (new File(FLAG).exists() ? " 存在" : " 不存在") + "\n"
                        + FLAG2 + (new File(FLAG2).exists() ? " 存在" : " 不存在") + "\n\n"
                        + "===== 待写入镜像 =====\n" + imgs.trim() + "\n\n"
                        + "===== 最近一次钩子日志 =====\n" + log.trim();
                ui.post(new Runnable() {
                    public void run() {
                        info.setText(text);
                    }
                });
            }
        }).start();
    }

    private String sh(String... cmd) {
        StringBuilder sb = new StringBuilder();
        try {
            Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line).append('\n');
            }
            p.waitFor();
        } catch (Throwable t) {
            sb.append("EX: ").append(t.toString());
        }
        return sb.toString();
    }
}
