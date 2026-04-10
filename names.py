import os
import re
from collections import defaultdict

# 定义匹配规则（严格按优先级顺序）
PATTERNS = [
    (
        "bd_head",
        re.compile(
            r"(?i)(?:bd_death_)?head(?!shot)|headshot|(?:_head_|_head\.)|^16head\b"
        ),
    ),
    ("bd_neck", re.compile(r"(?i)neck")),
    (
        "bd_larm",
        re.compile(
            r"(?i)left[_\-]?(?:arm|shoulder)|_larm\b|(?<=_)larm|^bd_death_leftarm"
        ),
    ),
    (
        "bd_rarm",
        re.compile(
            r"(?i)right[_\-]?(?:arm|shoulder)|_rarm\b|(?<=_)rarm|^bd_death_rightarm"
        ),
    ),
    (
        "bd_lleg",
        re.compile(r"(?i)left[_\-]?leg|_lleg\b|(?<=_)lleg|legs|^bd_death_leftleg"),
    ),  # 增加 legs
    (
        "bd_rleg",
        re.compile(r"(?i)right[_\-]?leg|_rleg\b|(?<=_)rleg|^bd_death_rightleg"),
    ),
    ("bd_pelvis", re.compile(r"(?i)pelvis|groin|gutshot|^16gutshot\b")),
    ("bd_back", re.compile(r"(?i)backstab|(?<=_)back\.|^16back\b")),  # 新增背部类别
    (
        "bd_torso",
        re.compile(
            r"(?i)(?:bd_death_)?torso|cod_\d+_torso|chest|stomach|(?<!\w)(?:16death[123]|16right|16left|16forward)\b|ex_mix_hit_gut"
        ),
    ),
    ("crawling", re.compile(r"(?i)crawl")),
    ("fire", re.compile(r"(?i)(?:fire|burn|flame|_onfire)")),
    ("club", re.compile(r"(?i)(?:club\d|slasher)")),
    ("exp", re.compile(r"(?i)(?:explosion|_exp_|flying|shotgun(?:back)?)")),
    ("moving", re.compile(r"(?i)(?:running|_run|trip|roll|faceplant)(?!_?onfire)")),
    ("bd_shotgun", re.compile(r"(?i)shotgun")),
    ("writhing", re.compile(r"(?i)writh")),
    ("ragdoll", re.compile(r"(?i)ragdoll")),
    ("crouch_die", re.compile(r"(?i)crouch[_\-]?die")),
    (
        "dying",
        re.compile(
            r"(?i)(?:^dying\d|^Death_(?!Running)|^16crouch_die|bd_death_leg_[0-9]|_leg_0[5-8]|Death_11_0[123]|Death_10)"
        ),
    ),
    ("UNKNOWN", re.compile(r".*")),
]


def classify_anim_file(filename: str) -> str:
    for category, pattern in PATTERNS:
        if pattern.search(filename):
            return category
    return "UNKNOWN"


def categorize_files(directory: str) -> dict:
    categories = defaultdict(list)
    for entry in os.listdir(directory):
        if entry.lower().endswith(".smd"):
            cat = classify_anim_file(entry)
            categories[cat].append(entry)
    return dict(categories)


def print_summary(categories: dict):
    total = sum(len(files) for files in categories.values())
    print(f"总文件数: {total}\n")
    order = [
        "bd_head",
        "bd_neck",
        "bd_larm",
        "bd_rarm",
        "bd_lleg",
        "bd_rleg",
        "bd_pelvis",
        "bd_back",
        "bd_torso",
        "crawling",
        "fire",
        "club",
        "exp",
        "moving",
        "bd_shotgun",
        "writhing",
        "ragdoll",
        "crouch_die",
        "dying",
        "UNKNOWN",
    ]
    for cat in order:
        files = categories.get(cat, [])
        if files:
            print(f"{cat:12} : {len(files):3} 个文件")
            # 可选：打印前几个示例
            # for f in sorted(files)[:3]:
            #     print(f"             - {f}")


if __name__ == "__main__":
    target_dir = r"C:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\backup\eda_3279383994\gmpublisher\models\brutal_deaths\decompiled 0.74\model_anim_modify_anims"
    if os.path.isdir(target_dir):
        result = categorize_files(target_dir)
        print_summary(result)
        with open("anim_classification_fixed.txt", "w", encoding="utf-8") as f:
            for cat, files in sorted(result.items()):
                f.write(f"\n[{cat}] ({len(files)} files)\n")
                for name in sorted(files):
                    f.write(f"  {name}\n")
        print("\n详细列表已保存至 anim_classification_fixed.txt")
    else:
        print("目录不存在，请检查路径。")
