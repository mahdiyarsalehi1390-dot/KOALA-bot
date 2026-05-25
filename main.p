import logging
import json
import os
from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup,
    ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove
)
from telegram.ext import (
    Application, CommandHandler, MessageHandler, CallbackQueryHandler,
    ContextTypes, filters, ConversationHandler
)

# ==================== تنظیمات ====================
BOT_TOKEN = "8686266988:AAG_c7rpiEqWV5v6g04FRmdCPKBaKcGnqjM"
ADMIN_ID = 8566998029
ADMIN_USERNAME = "@Abolfazlctt"
DATA_FILE = "data.json"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ==================== استیت‌های مکالمه ====================
(
    WAITING_RECEIPT,
    WAITING_CONFIG,
    WAITING_NEW_PRICE_GIG,
    WAITING_CARD_NUMBER,
    WAITING_REJECT_REASON,
    WAITING_CHARGE_AMOUNT,
    WAITING_CHARGE_RECEIPT,
    WAITING_BROADCAST_MSG,
    WAITING_RENEW_CONFIG,
    WAITING_RENEW_GIG,
    WAITING_RENEW_RECEIPT,
    WAITING_RENEW_REJECT_REASON,
    WAITING_FREE_REFERRAL,
) = range(13)

# ==================== مدیریت داده‌ها ====================
def load_data():
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "prices": {"per_gig": 208000},
        "card_number": "6037-XXXX-XXXX-XXXX",
        "card_owner": "ابوالفضل",
        "orders": {},
        "users": {},
        "renew_orders": {},
        "charge_orders": {},
        "referrals": {},
    }

def save_data(data):
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def get_or_create_user(data, user):
    uid = str(user.id)
    if uid not in data["users"]:
        data["users"][uid] = {
            "id": user.id,
            "name": user.full_name,
            "username": user.username or "ندارد",
            "balance": 0,
            "referral_count": 0,
            "free_config_claimed": False,
        }
    return data["users"][uid]

def calc_price(data, gig):
    return data["prices"]["per_gig"] * gig

# ==================== منوی پایین (Reply Keyboard) ====================
def main_reply_keyboard():
    keyboard = [
        [KeyboardButton("🛒 خرید سرویس"), KeyboardButton("💰 افزایش موجودی")],
        [KeyboardButton("👤 اطلاعات من"), KeyboardButton("🎁 سرویس رایگان")],
        [KeyboardButton("⚙️ مدیریت سرویس‌ها"), KeyboardButton("📞 ارتباط با پشتیبانی")],
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True, persistent=True)

# ==================== /start ====================
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    data = load_data()
    u = get_or_create_user(data, user)

    # ثبت رفرال
    args = context.args
    if args and args[0].startswith("ref_"):
        referrer_id = args[0].replace("ref_", "")
        uid = str(user.id)
        if referrer_id != uid and uid not in data.get("referrals", {}):
            data["referrals"][uid] = referrer_id
            if str(referrer_id) in data["users"]:
                data["users"][str(referrer_id)]["referral_count"] = \
                    data["users"][str(referrer_id)].get("referral_count", 0) + 1

    save_data(data)

    price = data["prices"]["per_gig"]
    text = (
        f"👋 سلام {user.first_name} عزیز!\n\n"
        "🔥 به ربات فروش V2Ray خوش اومدی!\n\n"
        f"💎 قیمت هر گیگ: {price:,} تومان\n"
        f"⚡ بدون محدودیت زمانی\n\n"
        "از منوی پایین یه گزینه انتخاب کن 👇"
    )
    await update.message.reply_text(text, reply_markup=main_reply_keyboard())

# ==================== هندل منوی پایین ====================
async def handle_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    user = update.effective_user
    data = load_data()
    get_or_create_user(data, user)
    save_data(data)

    if text == "🛒 خرید سرویس":
        await show_buy_menu(update, context)
    elif text == "💰 افزایش موجودی":
        await show_charge_menu(update, context)
    elif text == "👤 اطلاعات من":
        await show_my_info(update, context)
    elif text == "🎁 سرویس رایگان":
        await show_free_service(update, context)
    elif text == "⚙️ مدیریت سرویس‌ها":
        await show_manage_services(update, context)
    elif text == "📞 ارتباط با پشتیبانی":
        await show_support(update, context)

# ==================== خرید سرویس ====================
async def show_buy_menu(update: Update, cikontext: ContextTypes.DEFAULT_TYPE):
    data = load_data()
    p = data["prices"]["per_gig"]
    keyboard = []
    gigs = [1, 2, 3, 5, 10, 20, 30, 50]
    for g in gigs:
        price = calc_price(data, g)
        keyboard.append([InlineKeyboardButton(
            f"📦 {g} گیگ — {price:,} تومان",
            callback_data=f"order_{g}"
        )])
    keyboard.append([InlineKeyboardButton("❌ بستن", callback_data="close")])
    await update.message.reply_text(
        "📦 حجم مورد نظر رو انتخاب کن:",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

# ==================== افزایش موجودی ====================
async def show_charge_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    data = load_data()
    await update.message.reply_text(
        "💰 مبلغ شارژ موردنظر رو به تومان وارد کن:\n"
        "(مثلاً: 500000)",
        reply_markup=ReplyKeyboardRemove()
    )
    return WAITING_CHARGE_AMOUNT

async def receive_charge_amount(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        amount = int(update.message.text.replace(",", "").strip())
        if amount < 10000:
            await update.message.reply_text("❌ حداقل مبلغ ۱۰,۰۰۰ تومان است.", reply_markup=main_reply_keyboard())
            return ConversationHandler.END
        context.user_data["charge_amount"] = amount
        data = load_data()
        await update.message.reply_text(
            f"💳 برای شارژ {amount:,} تومان:\n\n"
            f"🏦 شماره کارت:\n`{data['card_number']}`\n"
            f"👤 به نام: {data['card_owner']}\n\n"
            "📸 بعد از واریز، فیش رو ارسال کن:",
            parse_mode="Markdown",
            reply_markup=main_reply_keyboard()
        )
        return WAITING_CHARGE_RECEIPT
    except:
        await update.message.reply_text("❌ فقط عدد وارد کن.", reply_markup=main_reply_keyboard())
        return ConversationHandler.END

async def receive_charge_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    amount = context.user_data.get("charge_amount", 0)
    charge_id = f"charge_{user.id}_{amount}"

    data = load_data()
    data.setdefault("charge_orders", {})[charge_id] = {
        "user_id": user.id,
        "username": user.username or "ندارد",
        "name": user.full_name,
        "amount": amount,
        "status": "pending"
    }
    save_data(data)

    caption = (
        f"💰 درخواست شارژ کیف پول\n\n"
        f"👤 {user.full_name}\n"
        f"🆔 {user.id}\n"
        f"📱 @{user.username or 'ندارد'}\n"
        f"💵 مبلغ: {amount:,} تومان\n"
        f"🔖 شناسه: {charge_id}"
    )
    keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton("✅ تایید و شارژ", callback_data=f"charge_ok_{charge_id}"),
        InlineKeyboardButton("❌ رد فیش", callback_data=f"charge_rej_{charge_id}"),
    ]])
    try:
        if update.message.photo:
            await context.bot.send_photo(ADMIN_ID, update.message.photo[-1].file_id, caption=caption, reply_markup=keyboard)
        elif update.message.document:
            await context.bot.send_document(ADMIN_ID, update.message.document.file_id, caption=caption, reply_markup=keyboard)
        else:
            await context.bot.send_message(ADMIN_ID, caption + f"\n\n📝 {update.message.text}", reply_markup=keyboard)
    except Exception as e:
        logger.error(e)

    await update.message.reply_text("✅ فیش دریافت شد! منتظر تایید ادمین باش.", reply_markup=main_reply_keyboard())
    return ConversationHandler.END

# ==================== اطلاعات من ====================
async def show_my_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    data = load_data()
    u = get_or_create_user(data, user)
    bot_username = (await context.bot.get_me()).username
    ref_link = f"https://t.me/{bot_username}?start=ref_{user.id}"
    ref_count = u.get("referral_count", 0)
    needed = 10 - (ref_count % 10)
    text = (
        f"👤 اطلاعات حساب شما:\n\n"
        f"🆔 آیدی: {user.id}\n"
        f"👤 نام: {user.full_name}\n"
        f"💎 موجودی کیف پول: {u.get('balance', 0):,} تومان\n\n"
        f"👥 زیرمجموعه‌ها: {ref_count} نفر\n"
        f"🎯 تا کانفیگ رایگان بعدی: {needed} نفر\n\n"
        f"🔗 لینک دعوت:\n{ref_link}"
    )
    await update.message.reply_text(text)

# ==================== سرویس رایگان ====================
async def show_free_service(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    data = load_data()
    u = get_or_create_user(data, user)
    ref_count = u.get("referral_count", 0)
    free_claimed = u.get("free_claimed_at", 0)
    earned = ref_count // 10

    text = (
        "🎁 سرویس رایگان با دعوت دوستان!\n\n"
        "📌 به ازای هر ۱۰ نفر دعوت، یک کانفیگ رایگان ۱ گیگ دریافت کن!\n\n"
        f"👥 زیرمجموعه‌های تو: {ref_count} نفر\n"
        f"🎯 کانفیگ رایگان قابل دریافت: {max(0, earned - free_claimed)}\n"
    )
    keyboard = []
    if earned > free_claimed:
        keyboard.append([InlineKeyboardButton("🎁 دریافت کانفیگ رایگان", callback_data="claim_free")])
    keyboard.append([InlineKeyboardButton("❌ بستن", callback_data="close")])
    await update.message.reply_text(text, reply_markup=InlineKeyboardMarkup(keyboard))

# ==================== مدیریت سرویس‌ها ====================
async def show_manage_services(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [InlineKeyboardButton("🔄 تمدید سرویس", callback_data="renew_service")],
        [InlineKeyboardButton("❌ بستن", callback_data="close")],
    ]
    await update.message.reply_text(
        "⚙️ مدیریت سرویس‌ها:\n\n"
        "برای تمدید سرویس روی دکمه زیر بزن و کانفیگت رو ارسال کن.",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

# ==================== پشتیبانی ====================
async def show_support(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"📞 برای پشتیبانی با ادمین در ارتباط باش:\n{ADMIN_USERNAME}\n\n"
        "⏰ ساعات پاسخگویی: همیشه 😊"
    )

# ==================== هندل دکمه‌های Inline ====================
async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    data = load_data()
    user = query.from_user

    # بستن
    if query.data == "close":
        await query.delete_message()
        return

    # ===== خرید =====
    elif query.data.startswith("order_"):
        gig = int(query.data.split("_")[1])
        price = calc_price(data, gig)
        u = get_or_create_user(data, user)
        balance = u.get("balance", 0)
        context.user_data["order_gig"] = gig
        context.user_data["order_price"] = price

        order_id = f"{user.id}_{gig}g"
        data["orders"][order_id] = {
            "user_id": user.id,
            "username": user.username or "ندارد",
            "name": user.full_name,
            "gig": gig,
            "price": price,
            "status": "pending"
        }
        save_data(data)

        if balance >= price:
            # پرداخت از کیف پول
            keyboard = [
                [InlineKeyboardButton("✅ پرداخت از کیف پول", callback_data=f"pay_wallet_{order_id}")],
                [InlineKeyboardButton("💳 پرداخت کارت به کارت", callback_data=f"pay_card_{order_id}")],
                [InlineKeyboardButton("❌ انصراف", callback_data="close")],
            ]
            await query.edit_message_text(
                f"📦 {gig} گیگ — {price:,} تومان\n\n"
                f"💎 موجودی کیف پول: {balance:,} تومان\n\n"
                "روش پرداخت رو انتخاب کن:",
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
        else:
            text = (
                f"💳 اطلاعات پرداخت:\n\n"
                f"📦 حجم: {gig} گیگ\n"
                f"💰 مبلغ: {price:,} تومان\n\n"
                f"🏦 شماره کارت:\n`{data['card_number']}`\n"
                f"👤 به نام: {data['card_owner']}\n\n"
                "📸 بعد از پرداخت، فیش رو ارسال کن."
            )
            keyboard = [[InlineKeyboardButton("❌ انصراف", callback_data="close")]]
            await query.edit_message_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="Markdown")
            return WAITING_RECEIPT

    # پرداخت از کیف پول
    elif query.data.startswith("pay_wallet_"):
        order_id = query.data.replace("pay_wallet_", "")
        if order_id not in data["orders"]:
            await query.edit_message_text("❌ سفارش یافت نشد.")
            return
        order = data["orders"][order_id]
        uid = str(order["user_id"])
        price = order["price"]
        if data["users"][uid]["balance"] < price:
            await query.edit_message_text("❌ موجودی کافی نیست.")
            return
        data["users"][uid]["balance"] -= price
        data["orders"][order_id]["status"] = "paid_wallet"
        save_data(data)
        caption = (
            f"🛒 سفارش جدید (کیف پول)\n\n"
            f"👤 {order['name']}\n"
            f"🆔 {order['user_id']}\n"
            f"📱 @{order['username']}\n"
            f"📦 {order['gig']} گیگ\n"
            f"💰 {price:,} تومان\n"
            f"🔖 شناسه: {order_id}"
        )
        keyboard = InlineKeyboardMarkup([[
            InlineKeyboardButton("📤 ارسال کانفیگ", callback_data=f"approve_{order_id}"),
        ]])
        await context.bot.send_message(ADMIN_ID, caption, reply_markup=keyboard)
        await query.edit_message_text("✅ پرداخت موفق! منتظر ارسال کانفیگ باش.")

    # پرداخت کارت
    elif query.data.startswith("pay_card_"):
        order_id = query.data.replace("pay_card_", "")
        order = data["orders"].get(order_id, {})
        text = (
            f"💳 اطلاعات پرداخت:\n\n"
            f"📦 {order.get('gig','?')} گیگ — {order.get('price',0):,} تومان\n\n"
            f"🏦 شماره کارت:\n`{data['card_number']}`\n"
            f"👤 به نام: {data['card_owner']}\n\n"
            "📸 فیش واریزی رو ارسال کن."
        )
        keyboard = [[InlineKeyboardButton("❌ انصراف", callback_data="close")]]
        await query.edit_message_text(text, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode="Markdown")
        context.user_data["order_gig"] = order.get("gig")
        context.user_data["order_price"] = order.get("price")
        return WAITING_RECEIPT

    # ===== تایید شارژ کیف پول =====
    elif query.data.startswith("charge_ok_"):
        if user.id != ADMIN_ID:
            return
        charge_id = query.data.replace("charge_ok_", "")
        charges = data.get("charge_orders", {})
        if charge_id in charges:
            ch = charges[charge_id]
            uid = str(ch["user_id"])
            get_or_create_user(data, type('U', (), {'id': ch["user_id"], 'full_name': ch["name"], 'username': ch["username"]})())
            data["users"][uid]["balance"] = data["users"][uid].get("balance", 0) + ch["amount"]
            charges[charge_id]["status"] = "approved"
            save_data(data)
            await context.bot.send_message(
                ch["user_id"],
                f"✅ کیف پول شما {ch['amount']:,} تومان شارژ شد!\n"
                f"💎 موجودی جدید: {data['users'][uid]['balance']:,} تومان"
            )
            await query.edit_message_caption(caption=query.message.caption + "\n\n✅ تایید شد")

    elif query.data.startswith("charge_rej_"):
        if user.id != ADMIN_ID:
            return
        charge_id = query.data.replace("charge_rej_", "")
        charges = data.get("charge_orders", {})
        if charge_id in charges:
            ch = charges[charge_id]
            charges[charge_id]["status"] = "rejected"
            save_data(data)
            await context.bot.send_message(
                ch["user_id"],
                "❌ فیش شما تایید نشد.\n"
                "📌 رسید شما فیک به نظر می‌رسد.\n"
                f"📞 {ADMIN_USERNAME}"
            )
            await query.edit_message_caption(caption=query.message.caption + "\n\n❌ رد شد")

    # ===== تایید/رد سفارش عادی =====
    elif query.data.startswith("approve_"):
        if user.id != ADMIN_ID:
            return
        order_id = query.data.replace("approve_", "")
        if order_id in data["orders"]:
            data["orders"][order_id]["status"] = "approved"
            save_data(data)
            context.user_data["pending_config_user"] = data["orders"][order_id]["user_id"]
            context.user_data["pending_order_id"] = order_id
            await query.edit_message_text(
                f"✅ سفارش تایید شد!\n"
                f"👤 {data['orders'][order_id]['name']}\n"
                f"📦 {data['orders'][order_id]['gig']} گیگ\n\n"
                "📤 کانفیگ رو اینجا بفرست:"
            )
            return WAITING_CONFIG

    elif query.data.startswith("reject_"):
        if user.id != ADMIN_ID:
            return
        order_id = query.data.replace("reject_", "")
        context.user_data["reject_order_id"] = order_id
        await query.edit_message_text("❌ دلیل رد سفارش رو بنویس:")
        return WAITING_REJECT_REASON

    # ===== تمدید سرویس =====
    elif query.data == "renew_service":
        await query.edit_message_text(
            "🔄 تمدید سرویس\n\n"
            "📋 کانفیگ فعلی‌ات رو اینجا ارسال کن:"
        )
        return WAITING_RENEW_CONFIG

    # ===== دریافت کانفیگ رایگان =====
    elif query.data == "claim_free":
        uid = str(user.id)
        u = data["users"].get(uid, {})
        ref_count = u.get("referral_count", 0)
        free_claimed = u.get("free_claimed_at", 0)
        earned = ref_count // 10
        if earned > free_claimed:
            data["users"][uid]["free_claimed_at"] = free_claimed + 1
            save_data(data)
            await context.bot.send_message(
                ADMIN_ID,
                f"🎁 درخواست کانفیگ رایگان\n\n"
                f"👤 {user.full_name}\n"
                f"🆔 {user.id}\n"
                f"📱 @{user.username or 'ندارد'}\n"
                f"📦 ۱ گیگ رایگان",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("📤 ارسال کانفیگ رایگان", callback_data=f"send_free_{user.id}")
                ]])
            )
            await query.edit_message_text("✅ درخواست ثبت شد! به زودی کانفیگ ارسال می‌شه.")
        else:
            await query.edit_message_text("❌ هنوز به تعداد کافی دعوت نداری.")

    elif query.data.startswith("send_free_"):
        if user.id != ADMIN_ID:
            return
        customer_id = int(query.data.replace("send_free_", ""))
        context.user_data["pending_config_user"] = customer_id
        context.user_data["pending_order_id"] = None
        await query.edit_message_text("📤 کانفیگ رایگان رو اینجا بفرست:")
        return WAITING_CONFIG

    # ===== تایید/رد تمدید =====
    elif query.data.startswith("renew_ok_"):
        if user.id != ADMIN_ID:
            return
        renew_id = query.data.replace("renew_ok_", "")
        if renew_id in data.get("renew_orders", {}):
            r = data["renew_orders"][renew_id]
            context.user_data["pending_renew_user"] = r["user_id"]
            context.user_data["pending_renew_id"] = renew_id
            data["renew_orders"][renew_id]["status"] = "approved"
            save_data(data)
            await query.edit_message_text(
                f"✅ تمدید تایید شد!\n"
                f"👤 {r['name']}\n"
                f"📦 {r['gig']} گیگ\n\n"
                "بعد از تمدید، پیام تایید رو بفرست یا کانفیگ جدید رو ارسال کن:",
            )
            return WAITING_CONFIG

    elif query.data.startswith("renew_rej_"):
         if user.id != ADMIN_ID:
            return
        renew_id = query.data.replace("renew_rej_", "")
        context.user_data["renew_reject_id"] = renew_id
        await query.edit_message_text("❌ دلیل رد تمدید رو بنویس:")
        return WAITING_RENEW_REJECT_REASON

    # ===== پنل ادمین =====
    elif query.data == "admin_stats":
        if user.id != ADMIN_ID:
            return
        total = len(data.get("orders", {}))
        approved = sum(1 for o in data["orders"].values() if o.get("status") in ("approved", "delivered"))
        pending = sum(1 for o in data["orders"].values() if o.get("status") == "pending")
        users = len(data.get("users", {}))
        total_balance = sum(u.get("balance", 0) for u in data["users"].values())
        charges = data.get("charge_orders", {})
        total_charged = sum(c["amount"] for c in charges.values() if c.get("status") == "approved")
        keyboard = [[InlineKeyboardButton("❌ بستن", callback_data="close")]]
        await query.edit_message_text(
            f"📊 آمار ربات:\n\n"
            f"👥 کل کاربران: {users}\n"
            f"📝 کل سفارش‌ها: {total}\n"
            f"⏳ در انتظار: {pending}\n"
            f"✅ تحویل داده شده: {approved}\n\n"
            f"💎 موجودی کل کیف پول‌ها: {total_balance:,} ت\n"
            f"💰 کل شارژ تایید شده: {total_charged:,} ت",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

    elif query.data == "change_gig_price":
        if user.id != ADMIN_ID:
            return
        await query.edit_message_text("💲 قیمت جدید هر گیگ رو به تومان وارد کن:")
        return WAITING_NEW_PRICE_GIG

    elif query.data == "admin_card":
        if user.id != ADMIN_ID:
            return
        await query.edit_message_text(f"💳 کارت فعلی: {data['card_number']}\n\nشماره کارت جدید رو وارد کن:")
        return WAITING_CARD_NUMBER

    elif query.data == "admin_back":
        if user.id != ADMIN_ID:
            return
        await query.edit_message_text("🛠 پنل ادمین:", reply_markup=admin_menu())

# ==================== دریافت فیش خرید ====================
async def receive_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    gig = context.user_data.get("order_gig", "?")
    price = context.user_data.get("order_price", 0)
    order_id = f"{user.id}_{gig}g"

    data = load_data()
    data["orders"].setdefault(order_id, {}).update({
        "user_id": user.id,
        "username": user.username or "ندارد",
        "name": user.full_name,
        "gig": gig,
        "price": price,
        "status": "pending"
    })
    save_data(data)

    caption = (
        f"🔔 فیش جدید!\n\n"
        f"👤 {user.full_name}\n"
        f"🆔 {user.id}\n"
        f"📱 @{user.username or 'ندارد'}\n"
        f"📦 {gig} گیگ\n"
        f"💰 {price:,} تومان\n"
        f"🔖 شناسه: {order_id}"
    )
    keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton("✅ تایید", callback_data=f"approve_{order_id}"),
        InlineKeyboardButton("❌ رد", callback_data=f"reject_{order_id}"),
    ]])
    try:
        if update.message.photo:
            await context.bot.send_photo(ADMIN_ID, update.message.photo[-1].file_id, caption=caption, reply_markup=keyboard)
        elif update.message.document:
            await context.bot.send_document(ADMIN_ID, update.message.document.file_id, caption=caption, reply_markup=keyboard)
        else:
            await context.bot.send_message(ADMIN_ID, caption + f"\n\n📝 {update.message.text}", reply_markup=keyboard)
    except Exception as e:
        logger.error(e)

    await update.message.reply_text("✅ فیش دریافت شد! منتظر تایید ادمین باش.", reply_markup=main_reply_keyboard())
    return ConversationHandler.END

# ==================== ارسال کانفیگ ====================
async def send_config(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return ConversationHandler.END
    customer_id = context.user_data.get("pending_config_user")
    order_id = context.user_data.get("pending_order_id")
    if not customer_id:
        await update.message.reply_text("❌ اطلاعات سفارش پیدا نشد.")
        return ConversationHandler.END
    try:
        await context.bot.send_message(
            chat_id=customer_id,
            text=(
                "🎉 سفارش شما تایید شد!\n\n"
                "📋 کانفیگ V2Ray:\n\n"
                f"`{update.message.text}`\n\n"
                f"✅ موفق باشی!\n📞 پشتیبانی: {ADMIN_USERNAME}"
            ),
            parse_mode="Markdown"
        )
        if order_id:
            data = load_data()
            if order_id in data["orders"]:
                data["orders"][order_id]["status"] = "delivered"
                save_data(data)
        await update.message.reply_text("✅ کانفیگ ارسال شد!")
    except Exception as e:
        await update.message.reply_text(f"❌ خطا: {e}")
    return ConversationHandler.END

# ==================== رد سفارش ====================
async def reject_order(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return ConversationHandler.END
    order_id = context.user_data.get("reject_order_id")
    reason = update.message.text
    data = load_data()
    if order_id and order_id in data["orders"]:
        customer_id = data["orders"][order_id]["user_id"]
        data["orders"][order_id]["status"] = "rejected"
        save_data(data)
        try:
            await context.bot.send_message(
                customer_id,
                f"❌ سفارش شما تایید نشد.\n📝 دلیل: {reason}\n\n"
                "💡 ممکنه فیش ارسالی معتبر نباشه.\n"
                f"📞 پشتیبانی: {ADMIN_USERNAME}"
            )
        except:
            pass
    await update.message.reply_text("✅ سفارش رد شد.")
    return ConversationHandler.END

# ==================== تمدید سرویس ====================
async def receive_renew_config(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["renew_config"] = update.message.text
    data = load_data()
    p = data["prices"]["per_gig"]
    keyboard = []
    for g in [1, 2, 3, 5, 10, 20]:
        price = calc_price(data, g)
        keyboard.append([InlineKeyboardButton(f"📦 {g} گیگ — {price:,} ت", callback_data=f"renew_gig_{g}")])
    keyboard.append([InlineKeyboardButton("❌ انصراف", callback_data="close")])
    await update.message.reply_text("📦 چقدر حجم میخوای تمدید کنی؟", reply_markup=InlineKeyboardMarkup(keyboard))
    return WAITING_RENEW_GIG

async def receive_renew_gig_cb(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    gig = int(query.data.split("_")[2])
    data = load_data()
    price = calc_price(data, gig)
    user = query.from_user
    context.user_data["renew_gig"] = gig
    context.user_data["renew_price"] = price

    renew_id = f"renew_{user.id}_{gig}g"
    data.setdefault("renew_orders", {})[renew_id] = {
        "user_id": user.id,
        "username": user.username or "ندارد",
        "name": user.full_name,
        "gig": gig,
        "price": price,
        "config": context.user_data.get("renew_config", ""),
        "status": "pending"
    }
    save_data(data)

    u = data["users"].get(str(user.id), {})
    balance = u.get("balance", 0)

    if balance >= price:
        keyboard = [
            [InlineKeyboardButton("✅ پرداخت از کیف پول", callback_data=f"renew_wallet_{renew_id}")],
            [InlineKeyboardButton("💳 کارت به کارت", callback_data=f"renew_card_{renew_id}")],
            [InlineKeyboardButton("❌ انصراف", callback_data="close")],
        ]
        await query.edit_message_text(
            f"📦 تمدید {gig} گیگ — {price:,} تومان\n"
            f"💎 موجودی: {balance:,} تومان\n\nروش پرداخت:",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    else:
        await query.edit_message_text(
            f"💳 پرداخت تمدید:\n\n"
            f"📦 {gig} گیگ — {price:,} تومان\n\n"
            f"🏦 شماره کارت:\n`{data['card_number']}`\n"
            f"👤 {data['card_owner']}\n\n"
            "📸 فیش واریزی رو ارسال کن:",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ انصراف", callback_data="close")]])
        )
        context.user_data["renew_id"] = renew_id
        return WAITING_RENEW_RECEIPT

async def receive_renew_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    renew_id = context.user_data.get("renew_id")
    data = load_data()
    renew = data.get("renew_orders", {}).get(renew_id, {})
    gig = renew.get("gig", "?")
    price = renew.get("price", 0)
    config = renew.get("config", "")

    caption = (
        f"🔄 درخواست تمدید سرویس\n\n"
        f"👤 {user.full_name}\n"
        f"🆔 {user.id}\n"
        f"📱 @{user.username or 'ندارد'}\n"
        f"📦 {gig} گیگ — {price:,} تومان\n"
        f"📋 کانفیگ: {config[:50]}...\n"
        f"🔖 شناسه: {renew_id}"
    )
    keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton("✅ تایید تمدید", callback_data=f"renew_ok_{renew_id}"),
        InlineKeyboardButton("❌ رد فیش", callback_data=f"renew_rej_{renew_id}"),
    ]])
    try:
        if update.message.photo:
            await context.bot.send_photo(ADMIN_ID, update.message.photo[-1].file_id, caption=caption, reply_markup=keyboard)
        elif update.message.document:
            await context.bot.send_document(ADMIN_ID, update.message.document.file_id, caption=caption, reply_markup=keyboard)
        else:
            await context.bot.send_message(ADMIN_ID, caption, reply_markup=keyboard)
    except Exception as e:
        logger.error(e)

    await update.message.reply_text("✅ درخواست تمدید ثبت شد! منتظر تایید ادمین باش.", reply_markup=main_reply_keyboard())
    return ConversationHandler.END

async def reject_renew(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return ConversationHandler.END
    renew_id = context.user_data.get("renew_reject_id")
    data = load_data()
    if renew_id and renew_id in data.get("renew_orders", {}):
        r = data["renew_orders"][renew_id]
        r["status"] = "rejected"
        save_data(data)
        try:
            await context.bot.send_message(
                r["user_id"],
                f"❌ درخواست تمدید شما رد شد.\n📝 دلیل: {update.message.text}\n\n"
                "💡 ممکنه فیش فیک باشه.\n"
                f"📞 {ADMIN_USERNAME}"
            )
        except:
            pass
    await update.message.reply_text("✅ تمدید رد شد.")
    return ConversationHandler.END

# ==================== پنل ادمین ====================
def admin_menu():
    keyboard = [
        [InlineKeyboardButton("💲 تغییر قیمت هر گیگ", callback_data="change_gig_price")],
        [InlineKeyboardButton("💳 تغییر شماره کارت", callback_data="admin_card")],
        [InlineKeyboardButton("📊 آمار", callback_data="admin_stats")],
        [InlineKeyboardButton("📢 ارسال پیام به همه", callback_data="broadcast")],
        [InlineKeyboardButton("❌ بستن", callback_data="close")],
    ]
    return InlineKeyboardMarkup(keyboard)

async def admin_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        await update.message.reply_text("❌ شما ادمین نیستید!")
        return
    data = load_data()
    text = (
        f"🛠 پنل ادمین\n\n"
        f"💲 قیمت هر گیگ: {data['prices']['per_gig']:,} تومان\n"
        f"💳 شماره کارت: {data['card_number']}"
    )
    await update.message.reply_text(text, reply_markup=admin_menu())

async def broadcast_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if query.from_user.id != ADMIN_ID:
        return
    await query.edit_message_text("📢 پیام خود را بنویس (به همه کاربران ارسال می‌شه):")
    return WAITING_BROADCAST_MSG

async def send_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return ConversationHandler.END
    data = load_data()
    msg = update.message.text
    sent, failed = 0, 0
    for uid, u in data["users"].items():
        try:
            await context.bot.send_message(int(uid), f"📢 پیام از ادمین:\n\n{msg}")
            sent += 1
        except:
            failed += 1
    await update.message.reply_text(f"✅ ارسال شد!\n📤 موفق: {sent}\n❌ ناموفق: {failed}")
    return ConversationHandler.END

async def update_gig_price(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return ConversationHandler.END
    try:
        new_price = int(update.message.text.replace(",", "").strip())
        data = load_data()
        data["prices"]["per_gig"] = new_price
        save_data(data)
        await update.message.reply_text(f"✅ قیمت هر گیگ: {new_price:,} تومان", reply_markup=admin_menu())
    except:
        await update.message.reply_text("❌ فقط عدد وارد کن.")
    return ConversationHandler.END

async def update_card(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return ConversationHandler.END
    data = load_data()
    data["card_number"] = update.message.text.strip()
    save_data(data)
    await update.message.reply_text(f"✅ شماره کارت: {data['card_number']}", reply_markup=admin_menu())
    return ConversationHandler.END

# ==================== main ====================
def main():
    app = Application.builder().token(BOT_TOKEN).build()

    # ConversationHandler اصلی
    conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(button_handler),
            MessageHandler(filters.TEXT & ~filters.COMMAND & filters.Regex(
                "^(🛒 خرید سرویس|💰 افزایش موجودی|👤 اطلاعات من|🎁 سرویس رایگان|⚙️ مدیریت سرویس‌ها|📞 ارتباط با پشتیبانی)$"
            ), handle_menu),
        ],
        states={
            WAITING_RECEIPT: [
                MessageHandler(filters.PHOTO | filters.Document.ALL | filters.TEXT & ~filters.COMMAND, receive_receipt),
                CallbackQueryHandler(button_handler),
            ],
            WAITING_CONFIG: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, send_config),
            ],
            WAITING_NEW_PRICE_GIG: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, update_gig_price),
            ],
            WAITING_CARD_NUMBER: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, update_card),
            ],
            WAITING_REJECT_REASON: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, reject_order),
            ],
            WAITING_CHARGE_AMOUNT: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, receive_charge_amount),
            ],
            WAITING_CHARGE_RECEIPT: [
                MessageHandler(filters.PHOTO | filters.Document.ALL | filters.TEXT & ~filters.COMMAND, receive_charge_receipt),
            ],
            WAITING_BROADCAST_MSG: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, send_broadcast),
            ],
            WAITING_RENEW_CONFIG: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, receive_renew_config),
            ],
            WAITING_RENEW_GIG: [
                CallbackQueryHandler(receive_renew_gig_cb, pattern="^renew_gig_"),
                CallbackQueryHandler(button_handler),
            ],
            WAITING_RENEW_RECEIPT: [
                MessageHandler(filters.PHOTO | filters.Document.ALL | filters.TEXT & ~filters.COMMAND, receive_renew_receipt),
            ],
            WAITING_RENEW_REJECT_REASON: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, reject_renew),
            ],
        },
        fallbacks=[CommandHandler("start", start)],
        per_user=True,
        per_chat=True,
        allow_reentry=True,
    )

    # broadcast callback جداگانه
    conv_broadcast = ConversationHandler(
        entry_points=[CallbackQueryHandler(broadcast_handler, pattern="^broadcast$")],
        states={
            WAITING_BROADCAST_MSG: [MessageHandler(filters.TEXT & ~filters.COMMAND, send_broadcast)],
        },
        fallbacks=[CommandHandler("start", start)],
        per_user=True,
        per_chat=True,
    )

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("admin", admin_command))
    app.add_handler(conv_broadcast)
    app.add_handler(conv)

    print("✅ ربات شروع به کار کرد!")
    app.run_polling()

if __name__ == "__main__":
    main()

