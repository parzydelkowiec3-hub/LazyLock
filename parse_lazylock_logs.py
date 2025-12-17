import re
import sys

log_file = "LazyLockSavedVariablesSoftLink.lua"

def parse_logs():
    try:
        with open(log_file, 'r') as f:
            content = f.read()

        # Find the Log table block
        # It usually looks like: ["Log"] = { ... },
        match = re.search(r'\["Log"\]\s*=\s*\{(.*?)\},', content, re.DOTALL)
        if not match:
            print("No 'Log' table found in file.")
            return

        log_content = match.group(1)
        
        # Parse individual log entries: [123] = "Message",
        # Regex to capture the message content inside quotes
        entries = re.findall(r'\[\d+\]\s*=\s*"(.*?)",', log_content)
        
        # Display the last 100 entries
        print(f"Found {len(entries)} log entries. Showing last 50:")
        for line in entries[-50:]:
            # Unescape quotes if needed (lua might escape them)
            line = line.replace('\\"', '"')
            print(line)

    except FileNotFoundError:
        print(f"File {log_file} not found.")
    except Exception as e:
        print(f"Error parsing logs: {e}")

if __name__ == "__main__":
    parse_logs()
