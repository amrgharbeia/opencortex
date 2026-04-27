#!/usr/bin/env python3
import sys
import json
import base64
from playwright.sync_api import sync_playwright

def run_bridge():
    # Read command from stdin
    try:
        raw_input = sys.stdin.read()
        if not raw_input:
            print(json.dumps({"status": "error", "message": "No input provided"}))
            return
        
        args = json.loads(raw_input)
    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Invalid JSON input: {str(e)}"}))
        return

    url = args.get("url")
    action = args.get("action", "extract_text")
    selector = args.get("selector", "body")

    if not url:
        print(json.dumps({"status": "error", "message": "No URL provided"}))
        return

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            
            # Navigate and wait for network to be idle
            page.goto(url, wait_until="networkidle")

            result = {"status": "success", "url": url}

            if action == "extract_text":
                result["content"] = page.inner_text(selector)
            elif action == "screenshot":
                screenshot_bytes = page.screenshot()
                result["screenshot_base64"] = base64.b64encode(screenshot_bytes).decode("utf-8")
            else:
                result["status"] = "error"
                result["message"] = f"Unknown action: {action}"

            browser.close()
            print(json.dumps(result))

    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Playwright Error: {str(e)}"}))

if __name__ == "__main__":
    run_bridge()
