async function post(url, data = {}) {
    const response = await fetch(`https://${GetParentResourceName()}/${url}`, {
        method: 'POST',
        mode: 'no-cors',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });

    return await response.json();
}

const truncateText = (text, max) => {
    return text.substr(0, max - 1) + (text.length > max ? '...' : '');
}

const chat = {
    container: $('.chat-messages'),
    input: $(".input-wrapper input"),

    size: 0,
    direction: "upToDown", // upToDown, downToUp
    active: false,
    timer: null,
    timerPush: null,
    oldMessages: [],
    oldMessagesIndex: -1,

    build(hideInput) {
        this.active = true;
        clearTimeout(this.timer);
        clearTimeout(this.timerPush);

        $("#chat").animate({ opacity: 1 }, 500);
        $(".chat-messages").css("overflow", 'overlay');

        if (!hideInput) {
            this.showFooter();
            this.input.focus();
        } else {
            this.hideFooter();
        }
    },

    queueHide() {
        clearTimeout(this.timer);
        clearTimeout(this.timerPush);

        this.timerPush = setTimeout(function () {
            chat.hide();
            $(".chat-messages").css("overflow", 'hidden');
        }, 10000);
    },

    escape(unsafe) {
        return String(unsafe)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;')
            .replace(/\n/g, '\\n');
    },

    colorize(str) {

        str = this.escape(str);


        let s = "<span>" + (str.replace(/\^([0-9a-z])/g, (str, color) => `</span><span class="color-${color}">`)) + "</span>";

        s = "<span>" + (s.replace(/#\{(\w+)\}/g, (str, color) => `</span><span style="color:#${color};">`)) + "</span>";

        s = "<span>" + (s.replace(/#rgb\[(\d+,\d+,\d+)\]/g, (str, color) => `</span><span style="color:rgb(${color});">`)) + "</span>";

        s = s.replace(/\[staff\](.*?)\[\/staff\]/g, '<strong>$1</strong>');

        let staffTags = {
            "founder": "FOUNDER",
            "Goatpower": "Goat Power",
            "GoatTeam": "Goat Team",
            "GoatFrozen": "Goat Frozen",
            "manager": "Manager",
            "Owner": "Community Helper",
            "patron": "Patron",
            "day1": "Day 1",
            "codetinator": "Co Detinator",
            "superModerator": "Super Moderator",
            "moderator": "Moderator",
            "helper": "Helper",
            "trialHelper": "Trial Helper",
            "bronzeAccount": "Bronze Account",
            "silverAccount": "Silver Account",
            "goldAccount": "Gold Account",
            "diamondAccount": "Diamond Account",
            "politie": "Politie",
            "smurd": "Smurd",
        };

        for (const [tag, displayName] of Object.entries(staffTags)) {
            let regex = new RegExp(`${tag}`, 'g');
            s = s.replace(regex, `<div class="staff-box staff-team ${tag}">${displayName}</div>`);
        }

        s = s.replace(/<span[^>]*><\/span[^>]*>/g, '');


        s = s.replace(/\\n/g, "<br>");

        s = s.replace(/\[medium\](.*?)\[\/medium\]/g, '<strong>$1</strong>');

        s = s.replace(/<span[^>]*><\/span[^>]*>/g, '');

        return s;
    },

    moveOldMessageIndex(up) {
        if (up && this.oldMessages.length > this.oldMessagesIndex + 1) {
            this.oldMessagesIndex += 1;
            this.input.val(this.oldMessages[this.oldMessagesIndex])
        } else if (!up && this.oldMessagesIndex - 1 >= 0) {
            this.oldMessagesIndex -= 1;
            this.input.val(this.oldMessages[this.oldMessagesIndex])
        } else if (!up && this.oldMessagesIndex - 1 === -1) {
            this.oldMessagesIndex = -1;
            this.input.val("");
        }
    },

    clear() {
        this.container.find(".chat-message").remove();
        this.container.find(".admin-action").remove();
        this.oldMessages = [];
        this.oldMessagesIndex = -1;
    },

    hideFooter() {
        $(".input-wrapper").hide();
    },

    showFooter() {
        $(".input-wrapper").show();
    },

    addMessage(msg) {
        if (!this.active) {
            this.build(true);
            this.queueHide();
        }

        msg = this.colorize(msg);


this.container[this.direction == "upToDown" ? "append" : "prepend"](`
    <div class="chat-message">
        <div style="display: flex; align-items: center; gap: 0.5vw;">
            ${msg}
        </div>
    </div>
`)


        this.container.animate({ scrollTop: this.container.prop("scrollHeight") }, 0);
    },

    adminAnn(title, msg) {
        if (!this.active) {
            this.build(true);
            this.queueHide();
        }

        msg = this.colorize(msg);

        this.container[this.direction == "upToDown" ? "append" : "prepend"](`
            <div class="admin-action">
                <div class="icon-box">
                    <img src="warning.svg" alt="">
                </div>
                <div class="flex-start">
                    <span>${title}</span>
                    <span>${msg}</span>
                </div>
            </div>
        `)


        this.container.animate({ scrollTop: this.container.prop("scrollHeight") }, 0);
    },


    destroy() {
        this.active = false;
        this.hideFooter();
        clearTimeout(this.timer);
        clearTimeout(this.timerPush);

        this.timer = setTimeout(function () {
            chat.hide();
            $(".chat-messages").css("overflow", 'hidden');
        }, 10000);

        post("setFocus", [false]);
    },

    hide(fullyHide) {
        this.active = false;
        $("#chat").animate({ opacity: !fullyHide ? 0.2 : 0 }, 1000)
    },

    ready() {
        var $this = this;

        $this.input.on('keydown', function (e) {
            if (e.key === 'Enter' || e.keyCode === 13) {

                var message = $this.input.val();

                if (message.trim().length == 0)
                    return $this.destroy();

                $this.input.val("");

                post("chatResult", [message]);

                $this.oldMessages.unshift(message);
                $this.oldMessagesIndex = -1;

                $this.destroy();

            } else if (e.which === 38 || e.which === 40) {
                e.preventDefault();
                $this.moveOldMessageIndex(e.which === 38);
            }
        });

        // this.clear();
        this.hideFooter();
        this.destroy();
        this.hide();
    }

}

chat.ready();

var minimumWidth = 1920;
var minimumHeigh = 1080;
window.onload = function () {
    changeSizeWidth();
    $(window).resize(changeSizeWidth);
}
function changeSizeWidth() {

    var zoomCountOne = $(window).width() / minimumWidth;
    var zoomCountTwo = $(window).height() / minimumHeigh;

    if (zoomCountOne < zoomCountTwo) {
        $('.main-chat').css('zoom', zoomCountOne);
        $('.chat-shadow').css('zoom', zoomCountOne);
    }
    else {
        $('.main-chat').css('zoom', zoomCountTwo);
        $('.chat-shadow').css('zoom', zoomCountTwo);
    }
}

window.addEventListener("keydown", function (event) {
    if (event.code == "Escape" && chat.active) {
        chat.destroy();
        chat.input.val("");
    }
})

window.addEventListener("message", function (event) {
    event.preventDefault();
    const data = event.data;

    if (data.act == "build") {
        chat.build();
    } else if (data.act == "clear") {
        $('.chat-shadow').hide();
        chat.clear();
    } else if (data.act == "adminAction") {
        $('.chat-shadow').show();
        chat.adminAnn(data.title, data.msg);
    } else if (data.act == "onMessage") {
        $('.chat-shadow').show();
        chat.addMessage(data.msg);
    }
})
