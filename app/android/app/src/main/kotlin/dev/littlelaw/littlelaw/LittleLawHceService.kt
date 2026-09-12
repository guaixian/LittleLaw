package dev.littlelaw.littlelaw

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/// NFC HCE(主机卡模拟)服务:把本机配对载荷模拟成 NDEF Type 4 标签,
/// 对方手机背部一碰即可读取(Android 读 / iPhone Core NFC 读均可)。
///
/// 载荷内容 = LanOobPayload 文本(LLT1....),由 MainActivity 静态字段注入,
/// 仅在用户主动开启"一碰配对"窗口期内有效。
class LittleLawHceService : HostApduService() {

    companion object {
        // NDEF 应用 AID(NFC Forum Type 4 Tag)。
        private val SELECT_AID = hex("00A4040007D276000085010100")
        private val SELECT_CC = hex("00A4000C02E103")
        private val SELECT_NDEF_FILE = hex("00A4000C02E104")
        private val OK = hex("9000")
        private val NOT_FOUND = hex("6A82")
        private val ERROR = hex("6F00")

        // 能力容器(CC):版本1.0,可读写,NDEF 文件 E104 最大 2048 字节。
        private val CC = hex("000F2000FF00FF0406E10408000000 00".replace(" ", ""))

        private fun hex(s: String): ByteArray =
            s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

        /// 构造 NDEF 文本记录(TNF=01,SR=1,类型 "T")。
        fun buildNdefFile(text: String): ByteArray {
            val textBytes = text.toByteArray(Charsets.UTF_8)
            val lang = "en".toByteArray(Charsets.US_ASCII)
            // 状态字节:UTF-8(0x00)+ 语言码长度
            val recordPayload = byteArrayOf(lang.size.toByte()) + lang + textBytes
            val ndef = byteArrayOf(
                0xD1.toByte(),                       // MB=1 ME=1 SR=1 TNF=1
                0x01,                                // type length
                recordPayload.size.toByte(),         // payload length
                0x54,                                // 'T'
            ) + recordPayload
            val nlen = ndef.size
            return byteArrayOf(
                (nlen shr 8).toByte(), (nlen and 0xFF).toByte()
            ) + ndef
        }
    }

    private var selectedFile = 0 // 0=none 1=cc 2=ndef

    override fun processCommandApdu(apdu: ByteArray?, extras: Bundle?): ByteArray {
        if (apdu == null) return ERROR
        return when {
            apdu.contentEquals(SELECT_AID) -> OK
            apdu.contentEquals(SELECT_CC) -> {
                selectedFile = 1; OK
            }
            apdu.contentEquals(SELECT_NDEF_FILE) -> {
                selectedFile = 2; OK
            }
            // READ BINARY: 00 B0 <offsetHi> <offsetLo> <len>
            apdu.size >= 5 && apdu[0] == 0x00.toByte() && apdu[1] == 0xB0.toByte() -> {
                val offset =
                    ((apdu[2].toInt() and 0xFF) shl 8) or (apdu[3].toInt() and 0xFF)
                val maxLen = apdu[4].toInt() and 0xFF
                val file = when (selectedFile) {
                    1 -> CC
                    2 -> {
                        val payload = MainActivity.nfcPayloadText
                        if (payload.isEmpty()) return NOT_FOUND
                        buildNdefFile(payload)
                    }
                    else -> return NOT_FOUND
                }
                if (offset >= file.size) return ERROR
                val end = minOf(offset + if (maxLen == 0) 256 else maxLen, file.size)
                file.copyOfRange(offset, end) + OK
            }
            else -> NOT_FOUND
        }
    }

    override fun onDeactivated(reason: Int) {
        selectedFile = 0
    }
}
