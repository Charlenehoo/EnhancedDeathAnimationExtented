import os
import re
import json
from collections import defaultdict

# 定义标签规则：每个规则返回一个标签列表
TAG_RULES = [
    # 身体部位
    (re.compile(r"(?i)head|neck|headshot|cranium"), ["head"]),
    (re.compile(r"(?i)chest|torso(?!_)"), ["chest"]),
    (re.compile(r"(?i)stomach|(?<=_)gut\b|hit_gut"), ["stomach"]),
    (re.compile(r"(?i)pelvis|groin|gutshot"), ["pelvis"]),
    (re.compile(r"(?i)left[_\-]?(?:arm|shoulder)|_larm\b|(?<=_)larm"), ["left_arm"]),
    (re.compile(r"(?i)right[_\-]?(?:arm|shoulder)|_rarm\b|(?<=_)rarm"), ["right_arm"]),
    (re.compile(r"(?i)left[_\-]?leg|_lleg\b|(?<=_)lleg"), ["left_leg"]),
    (re.compile(r"(?i)right[_\-]?leg|_rleg\b|(?<=_)rleg"), ["right_leg"]),
    (re.compile(r"(?i)legs\b"), ["left_leg", "right_leg"]),  # 复数双腿
    (
        re.compile(r"(?i)backstab|(?<=_)back\.|^16back\b|shotgunback|slasher_back"),
        ["back"],
    ),
    # 动作/姿态
    (re.compile(r"(?i)death|die|dying"), ["death"]),
    (re.compile(r"(?i)crawl"), ["crawling"]),
    (re.compile(r"(?i)run|running"), ["running"]),
    (re.compile(r"(?i)fall|flying|trip|explosion"), ["falling"]),
    (re.compile(r"(?i)writh"), ["writhing"]),
    (re.compile(r"(?i)ragdoll"), ["ragdoll"]),
    (re.compile(r"(?i)crouch"), ["crouching"]),
    # 伤害类型
    (re.compile(r"(?i)shotgun"), ["shotgun"]),
    (re.compile(r"(?i)explosion|_exp_"), ["explosion"]),
    (re.compile(r"(?i)fire|burn|flame|_onfire"), ["fire"]),
    (re.compile(r"(?i)slasher|backstab"), ["slash"]),
    (re.compile(r"(?i)club\d"), ["blunt"]),
    # 方向
    (re.compile(r"(?i)front|forward|^16forward\b"), ["front"]),
    (re.compile(r"(?i)back|backstab|^16back\b"), ["back"]),
    (re.compile(r"(?i)left|^16left\b"), ["left"]),
    (re.compile(r"(?i)right|^16right\b"), ["right"]),
    # 特殊修饰
    (re.compile(r"(?i)headshot"), ["headshot"]),
    (re.compile(r"(?i)multi"), ["multi"]),
    (re.compile(r"(?i)single"), ["single"]),
    (re.compile(r"(?i)short"), ["short"]),
    (re.compile(r"(?i)long"), ["long"]),
    (re.compile(r"(?i)revive|getup"), ["revive"]),
    (re.compile(r"(?i)idle"), ["idle"]),
]


def extract_tags(filename: str) -> set:
    """从文件名提取标签集合"""
    tags = set()
    for pattern, tag_list in TAG_RULES:
        if pattern.search(filename):
            tags.update(tag_list)
    # 默认标签
    if "death" not in tags and "crawling" not in tags and "ragdoll" not in tags:
        tags.add("death")  # 大部分是死亡动画
    if not any(
        t in tags
        for t in [
            "head",
            "chest",
            "stomach",
            "pelvis",
            "left_arm",
            "right_arm",
            "left_leg",
            "right_leg",
            "back",
        ]
    ):
        tags.add("full_body")
    if (
        "bullet" not in tags
        and "shotgun" not in tags
        and "explosion" not in tags
        and "fire" not in tags
        and "slash" not in tags
        and "blunt" not in tags
    ):
        tags.add("bullet")  # 默认枪弹
    return tags


def process_directory(directory: str) -> dict:
    """返回 {文件名: [标签列表]} 的字典"""
    result = {}
    for f in os.listdir(directory):
        if f.lower().endswith(".smd"):
            result[f] = sorted(extract_tags(f))
    return result


if __name__ == "__main__":
    target_dir = r"C:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\backup\eda_3279383994\gmpublisher\models\brutal_deaths\decompiled 0.74\model_anim_modify_anims"
    if os.path.isdir(target_dir):
        tags_dict = process_directory(target_dir)
        # 输出为 JSON
        with open("anim_tags.json", "w", encoding="utf-8") as f:
            json.dump(tags_dict, f, indent=2, ensure_ascii=False)
        # 输出为 Lua 表
        with open("anim_tags.lua", "w", encoding="utf-8") as f:
            f.write("local animTags = {\n")
            for name, tags in sorted(tags_dict.items()):
                tag_str = ", ".join(f'"{t}"' for t in tags)
                f.write(f'    ["{name}"] = {{{tag_str}}},\n')
            f.write("}\nreturn animTags\n")
        print(f"已处理 {len(tags_dict)} 个文件，标签数据已保存。")
    else:
        print("目录不存在")
