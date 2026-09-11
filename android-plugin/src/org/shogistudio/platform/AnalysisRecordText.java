package org.shogistudio.platform;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

/** Bounded record input; reports malformed text instead of replacing characters. */
public final class AnalysisRecordText {
    public static final int MAX_BYTES = 2097152;
    private AnalysisRecordText() { }

    public static String read(InputStream input) throws IOException {
        if (input == null) throw new IOException("No record stream");
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (bytes.size() + count > MAX_BYTES) throw new IOException("Record exceeds 2 MiB");
            bytes.write(buffer, 0, count);
        }
        return decode(bytes.toByteArray());
    }

    public static String decode(byte[] bytes) throws IOException {
        if (bytes.length > MAX_BYTES) throw new IOException("Record exceeds 2 MiB");
        String text;
        try {
            text = decodeAs(bytes, StandardCharsets.UTF_8);
        } catch (CharacterCodingException invalidUtf8) {
            text = decodeAs(bytes, Charset.forName("windows-31j"));
        }
        return text.startsWith("\uFEFF") ? text.substring(1) : text;
    }

    private static String decodeAs(byte[] bytes, Charset charset) throws CharacterCodingException {
        return charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
    }
}
