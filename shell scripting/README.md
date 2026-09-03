# System Information Script

`system_info.sh` displays basic system information and saves the running
processes to a text file.

## Commands Used

The script uses the required commands:

- `date` stores the current date in the `current_date` variable.
- `hostname` stores the computer name in the `host_name` variable.
- `whoami` stores the current user in the `user_name` variable.
- `read -p` asks for a report name.
- `mkdir -p` creates the `system-info-output` directory.
- `touch` creates the process report file.
- `df -h` prints disk usage.
- `ps aux` prints running processes.
- `ps aux > "$process_file"` saves running processes using output redirection.
- `echo` prints the report headings and stored values.

## Run

```bash
cd "shell scripting"
./system_info.sh
```

Example input:

```text
Enter a name for this system report: homework-report
```

The process list is saved to:

```text
system-info-output/homework-report-processes.txt
```

## Command Output

Verified output from the script:

```text
System Information
==================
Date: Fri Sep  4 12:22:08 AM IST 2026
Hostname: archlinux
Username: deepesh

Disk Usage:
Filesystem        Size  Used Avail Use% Mounted on
/dev/mapper/root  191G  101G   89G  54% /
/dev/nvme0n1p5    500M  218M  282M  44% /boot

Running Processes:
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0  21784 14452 ?        Ss   Sep03   0:02 /sbin/init
root           2  0.0  0.0      0     0 ?        S    Sep03   0:00 [kthreadd]

Process information saved to: system-info-output/homework-report-processes.txt
```

`df` and `ps` output depends on the machine where the script is run. The
complete process output is stored in the generated report file.