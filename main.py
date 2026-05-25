import logging
import os
from datetime import datetime
from telegram import Update, ReplyKeyboardMarkup, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters, ContextTypes

# ۱. تنظیمات لاگ
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# ۲. اطلاعات پایه ربات کوالا
TOKEN = "8686266988:AAG_c7rpiEqWV5v6g04FRmdCPKBaKcGnqjM"
ADMIN_ID = 8566998029  # ابوالفضل هدایتی
CHANNEL_USERNAME = "@koalavpnip"

# فایل‌های ذخیره اطلاعات
USERS_FILE = "users_data.txt"
SETTINGS_FILE = "settings.txt"
WALLETS_FILE = "wallets.txt"
REF_FILE = "referrals.txt"
CLIENT_FILE = "last_client.txt"
STATE_FILE = "admin_state.txt"

REQUIRED_REFERRALS = 5

def get_jalali_date():
    now = datetime.now()
    year = now.year - 621
    return f"{year}/{now.month}/{now.day}"

def load_settings():
    settings = {"per_gb": 290000, "test_price": 60000, "card": "6219861852656031"}
    if os.path.exists(SETTINGS_FILE):
        try:
            with open(SETTINGS_FILE, "r") as f:
                for line in f.read().splitlines():
                    if "=" in line:
                        k, v = line.split("=")
                        settings[k.strip()] = v.strip() if k.strip() == "card" else int(v.strip())
        except: pass
    return settings

def save_settings(per_gb, test_price, card):
    with open(SETTINGS_FILE, "w") as f:
        f.write(f"per_gb={per_gb}\ntest_price={test_price}\ncard={card}\n")

def get_wallet(user_id):
    if os.path.exists(WALLETS_FILE):
        with open(WALLETS_FILE, "r") as f:
            for line in f.read().splitlines():
                if f"{user_id}:" in line: return int(line.split(":")[1])
    return 0

def update_wallet(user_id, amount):
    wallets = {}
    if os.path.exists(WALLETS_FILE):
        with open(WALLETS_FILE, "r") as f:
            for line in f.read().splitlines():
                if ":" in line:
                    k, v = line.split(":")
                    wallets[k] = int(v)
    wallets[str(user_id)] = wallets.get(str(user_id), 0) + amount
    with open(WALLETS_FILE, "w") as f:
        for k, v in wallets.items(): f.write(f"{k}:{v}\n")

def get_user_info(user_id):
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, "r") as f:
            for line in f.read().splitlines():
                if f"{user_id}|" in line: return line.split("|")[1]
    return get_jalali_date()

def save_user(user_id):
    date_str = get_jalali_date()
    users = {}
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, "r") as f:
            for line in f.read().splitlines():
                if "|" in line:
                    k, v = line.split("|")
                    users[k] = v
    if str(user_id) not in users:
        users[str(user_id)] = date_str
        with open(USERS_FILE, "w") as f:
            for k, v in users.items(): f.write(f"{k}|{v}\n")

def get_refs(user_id):
    count = 0
    if os.path.exists(REF_FILE):
        with open(REF_FILE, "r") as f:
            for line in f.read().splitlines():
                if ":" in line and line.split(":")[1] == str(user_id): count += 1
    return count

def add_referral(new_user, inviter):
    if os.path.exists(REF_FILE):
        with open(REF_FILE, "r") as f:
            if f"{new_user}:" in f.read(): return False
    with open(REF_FILE, "a") as f: f.write(f"{new_user}:{inviter}\n")
    return True

def get_updated_plans():
    s = load_settings()
    per_gb = s["per_gb"]
    test_price = s["test_price"]
    return {
        "plan_test": {"name": "⏱️ کانفیگ تست اختصاصی", "price": test_price, "text": f"{test_price:,} تومان"},
        "plan_1g": {"name": "🟢 کانفیگ 1 گیگابایت", "price": per_gb, "text": f"{per_gb:,} تومان"},
        "plan_2g": {"name": "🟢 کانفیگ 2 گیگابایت", "price": per_gb*2, "text": f"{per_gb*2:,} تومان"},
        "plan_3g": {"name": "🟢 کانفیگ 3 گیگابایت", "price": per_gb*3, "text": f"{per_gb*3:,} تومان"},
        "plan_4g": {"name": "🟢 کانفیگ 4 گیگابایت", "price": per_gb*4, "text": f"{per_gb*4:,} تومان"},
        "plan_5g": {"name": "🟡 کانفیگ 5 گیگابایت", "price": per_gb*5, "text": f"{per_gb*5:,} تومان"},
        "plan_6g": {"name": "🟡 کانفیگ 6 گیگابایت", "price": per_gb*6, "text": f"{per_gb*6:,} تومان"},
        "plan_7g": {"name": "🟡 کانفیگ 7 گیگابایت", "price": per_gb*7, "text": f"{per_gb*7:,} تومان"},
        "plan_8g": {"name": "🔴 کانفیگ 8 گیگابایت", "price": per_gb*8, "text": f"{per_gb*8:,} تومان"},
        "plan_9g": {"name": "🔴 کانفیگ 9 گیگابایت", "price": per_gb*9, "text": f"{per_gb*9:,} تومان"},
        "plan_10g": {"name": "🔴 کانفیگ 10 گیگابایت", "price": per_gb*10, "text": f"{per_gb*10:,} تومان"}
    }

async def check_membership(user_id: int, context: ContextTypes.DEFAULT_TYPE) -> bool:
    try:
        member = await context.bot.get_chat_member(chat_id=CHANNEL_USERNAME, user_id=user_id)
        return member.status in ['creator', 'administrator', 'member']
    except: return False

async def show_bottom_menu(update: Update, context: ContextTypes.DEFAULT_TYPE, text_msg=None):
    keyboard = [
        ["🛒 خرید سرویس جدید"],
        ["👤 اطلاعات من", "🪙 افزایش موجودی"],
        ["⚙️ مدیریت سرویس‌ها", "🎉 سرویس رایگان"],
        ["💬 ارتباط با پشتیبانی"]
    ]
    reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)
    if text_msg is None:
        text_msg = "🏠 به منوی اصلی ربات BAX KOALA خوش آمدید. لطفاً از دکمه‌های زیر استفاده کنید:"
    if update.message:
        await update.message.reply_text(text_msg, reply_markup=reply_markup)
    elif update.callback_query:
        await context.bot.send_message(chat_id=update.effective_user.id, text=text_msg, reply_markup=reply_markup)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    save_user(user_id)
    
    if context.args and context.args[0].isdigit():
        inviter_id = int(context.args[0])
        if inviter_id != user_id:
            if add_referral(user_id, inviter_id):
                try: await context.bot.send_message(chat_id=inviter_id, text="🎉 یک کاربر جدید با لینک شما وارد ربات شد!")
                except: pass

    if not await check_membership(user_id, context):
        keyboard = [
            [InlineKeyboardButton("📢 عضویت در کانال کوالا", url=f"https://t.me/{CHANNEL_USERNAME.replace('@','')}")],
            [InlineKeyboardButton("✅ عضو شدم (تایید)", callback_data="check_join")]
        ]
        await update.message.reply_text("⚠️ برای استفاده از ربات BAX KOALA ابتدا باید در کانال ما عضو شوید:", reply_markup=InlineKeyboardMarkup(keyboard))
        return

    await show_bottom_menu(update, context)

async def handle_text_buttons(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = update.message.text
    PLANS = get_updated_plans()
    s = load_settings()

    # مدیریت بخش مدیریت (ارسال کانفیگ یا ثبت مبلغ شارژ دستی)
    if user_id == ADMIN_ID and os.path.exists(STATE_FILE) and os.path.exists(CLIENT_FILE):
        with open(STATE_FILE, "r") as f: state = f.read().strip()
        with open(CLIENT_FILE, "r") as f: target_user = int(f.read().strip())
        
        if state == "waiting_for_config":
            try:
                await context.bot.send_message(chat_id=target_user, text=f"🚀 **کانفیگ اختصاصی شما صادر شد:**\n\n`{text}`", parse_mode="Markdown")
                await update.message.reply_text(f"✅ کانفیگ با موفقیت به مشتری ({target_user}) تحویل داده شد.")
                if os.path.exists(CLIENT_FILE): os.remove(CLIENT_FILE)
                if os.path.exists(STATE_FILE): os.remove(STATE_FILE)
            except Exception as e:
                await update.message.reply_text(f"❌ خطا در ارسال پیام به مشتری: {e}")
            return
            
        elif state == "waiting_for_amount":
            try:
                charge_amount = int(text)
                update_wallet(target_user, charge_amount)
                await context.bot.send_message(chat_id=target_user, text=f"🎉 کیف پول شما با موفقیت به مبلغ {charge_amount:,} تومان شارژ شد!")
                await update.message.reply_text(f"✅ مبلغ {charge_amount:,} تومان با موفقیت به کیف پول کاربر `{target_user}` اضافه شد.")
                if os.path.exists(CLIENT_FILE): os.remove(CLIENT_FILE)
                if os.path.exists(STATE_FILE): os.remove(STATE_FILE)
            except ValueError:
                await update.message.reply_text("❌ لطفاً فقط عدد انگلیسی وارد کنید.")
            return

    if not await check_membership(user_id, context):
        await start(update, context)
        return

    # دریافت مبلغ دلخواه از کاربر برای شارژ کیف پول
    if context.user_data.get('waiting_custom_amount'):
        try:
            amount = int(text)
            if amount < 5000:
                await update.message.reply_text("❌ حداقل مبلغ شارژ ۵,۰۰۰ تومان می‌باشد. لطفاً مجدداً مبلغ را وارد کنید:")
                return
            context.user_data['waiting_custom_amount'] = False
            context.user_data['action'] = 'charge'
            context.user_data['charge_amount'] = amount
            
            card_text = f"💳 **درخواست شارژ کیف پول بمبلغ {amount:,} تومان**\n\nلطفاً مبلغ فوق را به شماره کارت زیر واریز نمایید:\n\n`{s['card']}`\n👤 به نام: ابوالفضل هدایتی\n\n📸 پس از واریز وجه، **فقط عکس فیش** را در همینجا ارسال کنید."
            await update.message.reply_text(card_text, parse_mode="Markdown")
        except ValueError:
            await update.message.reply_text("❌ لطفاً مبلغ را فقط به صورت عدد (به انگلیسی) وارد کنید:")
        return

    if text == "🛒 خرید سرویس جدید":
        keyboard = []
        for k, v in PLANS.items():
            keyboard.append([InlineKeyboardButton(f"{v['name']} ➖ {v['text']}", callback_data=f"select_{k}")])
        await update.message.reply_text("📋 پلان مورد نظر خود را انتخاب کنید:", reply_markup=InlineKeyboardMarkup(keyboard))

    elif text == "👤 اطلاعات من":
        refs = get_refs(user_id)
        join_date = get_user_info(user_id)
        balance = get_wallet(user_id)
        info_text = (
            f"─── 👤 اطلاعات حساب شما ───\n\n"
            f"👤 شناسه کاربری: `{user_id}`\n"
            f"👥 تعداد زیرمجموعه‌ها: {refs} عدد\n"
            f"📊 موجودی کیف پول: {balance:,} تومان\n"
            f"📈 قیمت پایه هر گیگ: {s['per_gb']:,} تومان\n\n"
            f"📅 تاریخ عضویت: {join_date}"
        )
        inline_kb = [[InlineKeyboardButton("🎫 اعمال کد تخفیف", callback_data="apply_promo")]]
        await update.message.reply_text(info_text, reply_markup=InlineKeyboardMarkup(inline_kb), parse_mode="Markdown")

    elif text == "🪙 افزایش موجودی":
        per_gb = s["per_gb"]
        inline_kb = [
            [InlineKeyboardButton(f"💵 شارژ معادل ۱ گیگ ({per_gb:,} تومان)", callback_data=f"reqcharge_{per_gb}")],
            [InlineKeyboardButton(f"💵 شارژ معادل ۲ گیگ ({per_gb*2:,} تومان)", callback_data=f"reqcharge_{per_gb*2}")],
            [InlineKeyboardButton(f"💵 شارژ معادل ۳ گیگ ({per_gb*3:,} تومان)", callback_data=f"reqcharge_{per_gb*3}")],
            [InlineKeyboardButton(f"💵 شارژ معادل ۵ گیگ ({per_gb*5:,} تومان)", callback_data=f"reqcharge_{per_gb*5}")],
            [InlineKeyboardButton("✍️ ورود مبلغ دلخواه (تومان)", callback_data="custom_charge")]
        ]
        await update.message.reply_text("🪙 لطفاً مبلغی که می‌خواهید کیف پولتان شارژ شود را انتخاب یا به صورت دلخواه وارد کنید:", reply_markup=InlineKeyboardMarkup(inline_kb))

    elif text == "⚙️ مدیریت سرویس‌ها":
        await update.message.reply_text("‼️ شما هیچ سرویسی ندارید.\nابتدا از بخش ' خرید سرویس جدید ' سرویسی تهیه فرمایید.")

    elif text == "🎉 سرویس رایگان":
        bot_info = await context.bot.get_me()
        refs = get_refs(user_id)
        ref_link = f"https://t.me/{bot_info.username}?start={user_id}"
        ref_text = f"👥 **سیستم زیرمجموعه‌گیری کوالا VPN**\n\n🔗 لینک اختصاصی شما:\n{ref_link}\n\n📊 تعداد افراد دعوت شده: {refs} نفر\n🎁 هدیه: با دعوت {REQUIRED_REFERRALS} نفر، یک کانفیگ رایگان بگیرید!"
        keyboard = []
        if refs >= REQUIRED_REFERRALS:
            keyboard.append([InlineKeyboardButton("🎁 دریافت کانفیگ جایزه", callback_data="claim_reward")])
        await update.message.reply_text(ref_text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="Markdown")

    elif text == "💬 ارتباط با پشتیبانی":
        kb = [[InlineKeyboardButton("👨‍💻 پیام به پشتیبانی اصلی", url="https://t.me/Abolfazlctt")]]
        await update.message.reply_text("جهت ارتباط با مدیریت و پشتیبانی به پی‌وی زیر پیام دهید:", reply_markup=InlineKeyboardMarkup(kb))

async def callback_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    user_id = query.from_user.id
    PLANS = get_updated_plans()
    s = load_settings()

    if query.data == "check_join":
        if await check_membership(user_id, context): await show_bottom_menu(update, context, "✅ عضویت شما تایید شد!")
        else: await context.bot.send_message(chat_id=user_id, text="❌ هنوز عضو کانال نشده‌اید.")

    elif query.data == "apply_promo":
        await context.bot.send_message(chat_id=user_id, text="🎫 در حال حاضر کد تخفیف فعالی وجود ندارد.")

    elif query.data == "custom_charge":
        context.user_data['waiting_custom_amount'] = True
        await context.bot.send_message(chat_id=user_id, text="✍️ لطفاً مبلغ مورد نظر خود را برای شارژ کیف پول به **تومان** وارد کنید (مثال: 150000):")

    elif query.data.startswith("reqcharge_"):
        amount = int(query.data.split("_")[1])
        context.user_data['action'] = 'charge'
        context.user_data['charge_amount'] = amount
        text = f"💳 **درخواست شارژ کیف پول بمبلغ {amount:,} تومان**\n\nلطفاً مبلغ فوق را به شماره کارت زیر واریز نمایید:\n\n`{s['card']}`\n👤 به نام: ابوالفضل هدایتی\n\n📸 پس از واریز وجه، **فقط عکس فیش** را ارسال کنید."
        await query.edit_message_text(text, parse_mode="Markdown")

    elif query.data.startswith("select_"):
        plan_id = query.data.replace("select_", "")
        plan_info = PLANS.get(plan_id)
        balance = get_wallet(user_id)
        context.user_data['action'] = 'buy'
        context.user_data['selected_plan'] = plan_info['name']
        context.user_data['selected_price'] = plan_info['price']
        
        text = f"🛍️ **پلان:** {plan_info['name']}\n💰 **قیمت:** {plan_info['text']}\n💵 **موجودی شما:** {balance:,} تومان\n\nروش پرداخت را انتخاب کنید:"
        keyboard = [[InlineKeyboardButton("💳 کارت به کارت (ارسال فیش)", callback_data="pay_card")]]
        if balance >= plan_info['price']:
            keyboard.append([InlineKeyboardButton("💰 پرداخت سریع با کیف پول", callback_data="pay_wallet")])
        await query.edit_message_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="Markdown")

    elif query.data == "pay_card":
        plan_name = context.user_data.get('selected_plan')
        price_text = f"{context.user_data.get('selected_price', 0):,} تومان"
        text = f"🛍️ **پلان:** {plan_name}\n💰 **قیمت:** {price_text}\n\n💳 شماره کارت جهت واریز:\n`{s['card']}`\n👤 به نام: ابوالفضل هدایتی\n\n📸 پس از واریز، عکس فیش را در همینجا ارسال کنید."
        await query.edit_message_text(text, parse_mode="Markdown")

    elif query.data == "pay_wallet":
        plan_name = context.user_data.get('selected_plan')
        price = context.user_data.get('selected_price', 0)
        if get_wallet(user_id) >= price:
            update_wallet(user_id, -price)
            admin_keyboard = [[InlineKeyboardButton("✅ ارسال کانفیگ", callback_data=f"approve_{user_id}")]]
            await context.bot.send_message(chat_id=ADMIN_ID, text=f"💰 **خرید آنی با کیف پول!**\n\n👤 مشتری: {query.from_user.first_name}\n🆔 آیدی: `{user_id}`\n🛍️ پلان: {plan_name}\n\n(پول از کیف پول کسر شد؛ جهت فرستادن کانفیگ دکمه زیر را بزنید).", reply_markup=InlineKeyboardMarkup(admin_keyboard))
            await query.edit_message_text("✅ پرداخت با کیف پول موفقیت‌آمیز بود! درخواست به ادمین ارسال شد.")

    elif query.data.startswith("approve_"):
        client_id = query.data.split("_")[1]
        with open(CLIENT_FILE, "w") as f: f.write(client_id)
        with open(STATE_FILE, "w") as f: f.write("waiting_for_config")
        await query.message.reply_text(f"🟢 خرید یا فیش کاربر `{client_id}` تایید شد.\n\n👇 اکنون متن کانفیگ را بفرستید:")

    elif query.data.startswith("wallet_input_amount_"):
        client_id = query.data.split("_")[3]
        with open(CLIENT_FILE, "w") as f: f.write(client_id)
        with open(STATE_FILE, "w") as f: f.write("waiting_for_amount")
        await query.message.reply_text(f"🟢 فیش کاربر `{client_id}` را رویت کردید.\n\n👇 مبلغ دلخواه را به **عددی و به تومان** وارد کنید تا کیف پول کاربر شارژ شود:")

async def handle_messages(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if update.message.photo:
        action = context.user_data.get('action', 'buy')
        if action == 'charge':
            amount = context.user_data.get('charge_amount', 0)
            admin_kb = [[InlineKeyboardButton("✅ ثبت مبلغ و شارژ کیف پول", callback_data=f"wallet_input_amount_{user_id}")]]
            
            caption_text = f"🪙 **فیش افزایش موجودی کیف پول!**\n\n👤 کاربر: {update.effective_user.first_name}\n🆔 آیدی: `{user_id}`\n💵 مبلغ اعلامی کاربر: {amount:,} تومان\n\n📌 برای ثبت فیش و تعیین مبلغ واریزی دکمه زیر را بزنید."
            await context.bot.send_photo(chat_id=ADMIN_ID, photo=update.message.photo[-1].file_id, caption=caption_text, reply_markup=InlineKeyboardMarkup(admin_kb))
            await update.message.reply_text("✅ فیش شارژ برای مدیریت ارسال شد و پس از تایید حساب شما شارژ می‌شود.")
            context.user_data['action'] = 'buy'
        else:
            plan_name = context.user_data.get('selected_plan', 'نامشخص')
            admin_keyboard = [[InlineKeyboardButton("✅ تایید فیش و خرید", callback_data=f"approve_{user_id}")]]
            await context.bot.send_photo(chat_id=ADMIN_ID, photo=update.message.photo[-1].file_id, caption=f"🚨 **فیش خرید عادی کانفیگ!**\n\n👤 مشتری: {update.effective_user.first_name}\n🆔 آیدی: `{user_id}`\n🛍️ پلان: {plan_name}\n\n📌 پس از زدن دکمه تایید، باید متن کانفیگ را بفرستید.", reply_markup=InlineKeyboardMarkup(admin_keyboard))
            await update.message.reply_text("✅ فیش خرید شما برای مدیریت ارسال شد.")

async def set_price(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID or not context.args: return
    try:
        new_price = int(context.args[0])
        s = load_settings()
        save_settings(new_price, s["test_price"], s["card"])
        await update.message.reply_text(f"✅ قیمت هر گیگابایت به {new_price:,} تومان تغییر کرد.")
    except: pass

async def set_card(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID or not context.args: return
    new_card = context.args[0]
    s = load_settings()
    save_settings(s["per_gb"], s["test_price"], new_card)
    await update.message.reply_text(f"✅ شماره کارت ربات تغییر یافت به:\n`{new_card}`", parse_mode="Markdown")

def main():
    app = Application.builder().token(TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("setprice", set_price))
    app.add_handler(CommandHandler("setcard", set_card))
    app.add_handler(CallbackQueryHandler(callback_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_buttons))
    app.add_handler(MessageHandler(filters.PHOTO, handle_messages))
    print("🚀 ربات کوالا پچ شد... در حال روشن شدن")
    app.run_polling()

if __name__ == '__main__':
    main()
