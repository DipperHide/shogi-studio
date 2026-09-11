import org.shogistudio.platform.AnalysisRecordText;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.Executors;

public final class AnalysisRecordTextTest {
    private static int checks;
    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }
    private static void rejected(InputStream source, String message) throws Exception {
        boolean failed = false;
        try { AnalysisRecordText.read(source); } catch (IOException expected) { failed = true; }
        check(failed, message);
    }
    public static void main(String[] args) throws Exception {
        String sample = "先手：伊藤匠\n後手：藤井聡太\n*注釈を保持\n1 ７六歩(77)";
        check(AnalysisRecordText.decode(sample.getBytes(StandardCharsets.UTF_8)).equals(sample), "UTF-8 record");
        check(AnalysisRecordText.decode(("\uFEFF"+sample).getBytes(StandardCharsets.UTF_8)).equals(sample), "UTF-8 BOM");
        check(AnalysisRecordText.decode(sample.getBytes(Charset.forName("windows-31j"))).equals(sample), "CP932 record");
        check(AnalysisRecordText.decode("日本語 ｶﾀｶﾅ ① 髙".getBytes(Charset.forName("windows-31j"))).equals("日本語 ｶﾀｶﾅ ① 髙"), "CP932 extensions and halfwidth text");
        String unicode = "中文评论 🐉";
        check(AnalysisRecordText.decode(unicode.getBytes(StandardCharsets.UTF_8)).equals(unicode), "UTF-8 supplementary characters");
        check(AnalysisRecordText.read(new ByteArrayInputStream(new byte[0])).isEmpty(), "empty stream");
        byte[] boundary = new byte[AnalysisRecordText.MAX_BYTES]; Arrays.fill(boundary, (byte)'x');
        check(AnalysisRecordText.read(new ByteArrayInputStream(boundary)).length() == boundary.length, "exact byte limit");
        rejected(new ByteArrayInputStream(new byte[AnalysisRecordText.MAX_BYTES + 1]), "oversize input");
        rejected(new ByteArrayInputStream(new byte[]{(byte)0x81}), "truncated CP932 character");
        rejected(new ByteArrayInputStream(new byte[]{(byte)0xff,(byte)0xfe}), "unsupported malformed text");
        rejected(null, "null stream");
        rejected(new InputStream() { public int read() throws IOException { throw new IOException("unavailable provider"); } }, "I/O errors propagate");
        byte[] raw = sample.getBytes(Charset.forName("windows-31j"));
        InputStream chunks = new ByteArrayInputStream(raw) {
            public synchronized int read(byte[] buffer, int offset, int length) { return super.read(buffer,offset,Math.min(length,1)); }
        };
        check(AnalysisRecordText.read(chunks).equals(sample), "split multibyte characters across reads");
        var executor = Executors.newFixedThreadPool(2);
        try {
            var one = executor.submit(() -> AnalysisRecordText.decode(raw));
            var two = executor.submit(() -> AnalysisRecordText.decode(unicode.getBytes(StandardCharsets.UTF_8)));
            check(one.get().equals(sample) && two.get().equals(unicode), "parallel requests keep separate decoder state");
        } finally { executor.shutdown(); }
        System.out.println("{\"checks\":"+checks+",\"failures\":[]}");
    }
}
