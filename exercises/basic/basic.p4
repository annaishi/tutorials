// SPDX-License-Identifier: Apache-2.0
/* -*- P4_16 -*- */
// P4言語の基本的な定義をインポート
#include <core.p4>
// BMv2 (Behavioral Model version 2) のアーキテクチャ定義をインポート
// v1modelは標準的なスイッチのパイプラインモデルを提供
#include <v1model.p4>

// EthernetフレームのEtherTypeフィールドでIPv4を示す定数（16進数で0x0800）
const bit<16> TYPE_IPV4 = 0x800;

/*************************************************************************
*********************** H E A D E R S  ***********************************
* This program skeleton defines minimal Ethernet and IPv4 headers and    *
* a simple LPM (Longest-Prefix Match) IPv4 forwarding pipeline.          *
* The exercise intentionally leaves TODOs for learners to implement.     *
*************************************************************************/

// カスタム型定義: コードの可読性を高めるため
typedef bit<9>  egressSpec_t;   // 出力ポート番号（BMv2では9ビット、最大512ポート）
typedef bit<48> macAddr_t;      // MACアドレス（48ビット = 6バイト）
typedef bit<32> ip4Addr_t;      // IPv4アドレス（32ビット = 4バイト）

// Ethernetフレームのヘッダー定義（合計14バイト）
header ethernet_t {
    macAddr_t dstAddr;   // 宛先MACアドレス（6バイト）
    macAddr_t srcAddr;   // 送信元MACアドレス（6バイト）
    bit<16>   etherType; // 上位層のプロトコルタイプ（2バイト）例: 0x0800=IPv4
}

// IPv4ヘッダー定義（最小20バイト）
// RFC 791に準拠した標準的なIPv4ヘッダー構造
header ipv4_t {
    bit<4>    version;        // IPバージョン（IPv4の場合は4）
    bit<4>    ihl;            // ヘッダー長（Internet Header Length）単位は4バイト
    bit<8>    diffserv;       // サービス品質（Differentiated Services）
    bit<16>   totalLen;       // パケット全体の長さ（ヘッダー + データ）
    bit<16>   identification; // フラグメント識別子
    bit<3>    flags;          // フラグメント制御フラグ
    bit<13>   fragOffset;     // フラグメントオフセット
    bit<8>    ttl;            // Time To Live（ホップ数の上限）
    bit<8>    protocol;       // 上位層プロトコル（例: 6=TCP, 17=UDP）
    bit<16>   hdrChecksum;    // ヘッダーのチェックサム
    ip4Addr_t srcAddr;        // 送信元IPアドレス（4バイト）
    ip4Addr_t dstAddr;        // 宛先IPアドレス（4バイト）
}

// ユーザー定義メタデータ構造体
// パイプライン内で情報を伝達するために使用（この演習では未使用）
struct metadata {
    /* empty */
}

// パケット内のすべてのヘッダーをまとめる構造体
// パーサーで抽出され、パイプライン全体で使用される
struct headers {
    ethernet_t   ethernet;  // Ethernetヘッダー
    ipv4_t       ipv4;      // IPv4ヘッダー
}

/*************************************************************************
*********************** P A R S E R  *************************************
* New to P4? A typical parser does this:
*   start -> parse_ethernet
*   parse_ethernet:
*       if etherType == TYPE_IPV4 -> parse_ipv4
*       else accept
*   parse_ipv4 -> accept
* This skeleton leaves the actual states as a TODO to implement later.   *
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        /* TODO: add parser logic
         * Suggested outline:
         *   1) Extract Ethernet: packet.extract(hdr.ethernet);
         *   2) If hdr.ethernet.etherType == TYPE_IPV4 -> parse IPv4
         *   3) Otherwise -> transition accept
         */
        // パーサーの開始状態: まずEthernetヘッダーの解析に遷移
        transition parse_ethernet;
    }

    state parse_ethernet {
        // パケットからEthernetヘッダー（14バイト）を抽出
        packet.extract(hdr.ethernet);
        // EtherTypeフィールドの値に応じて次の状態を決定
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;  // IPv4パケットの場合、IPv4ヘッダーの解析へ
            default: accept;         // それ以外のプロトコルは解析終了
        }
    }

    state parse_ipv4 {
        // パケットからIPv4ヘッダー（20バイト）を抽出
        packet.extract(hdr.ipv4);
        // 解析完了: パイプライン処理へ進む
        transition accept; // パーサーでの処理は終了
    }
}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
* パーサーの後、Ingressパイプラインの前に実行される                      *
* 受信したパケットのチェックサムを検証する（この演習では未実装）         *
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
        // チェックサム検証ロジックをここに実装可能
        // 例: verify_checksum()を使ってIPv4ヘッダーのチェックサムを検証
    }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
* High-level intent:
*   - Do an LPM lookup on IPv4 dstAddr
*   - On hit, call ipv4_forward(next-hop MAC, output port)
*   - Otherwise, drop or NoAction (as configured)                         *
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    // パケットを破棄するアクション
    // mark_to_drop()を呼ぶことで、パケットは出力されずに破棄される
    action drop() {
        mark_to_drop(standard_metadata);
    }

    /*********************************************************************
     * NOTE FOR NEW READERS:
     * 'ipv4_forward(dstAddr, port)' is invoked by table 'ipv4_lpm'.
     *
     * The values for 'dstAddr' and 'port' are *action data* supplied by
     * the control plane when it installs entries in 'ipv4_lpm'.
     *
     * They mean:
     *   - dstAddr  => Ethernet destination MAC for the next hop
     *   - port     => output port (ultimately written to standard_metadata.egress_spec)
     *
     * Example (BMv2 simple_switch_CLI):
     *   table_add ipv4_lpm ipv4_forward 10.0.1.1/32 => 00:00:00:00:01:00 1
     * which passes MAC=00:00:00:00:01:00 and PORT=1 as action parameters
     * into ipv4_forward(dstAddr, port).
     *********************************************************************/
    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        /*
            Action function for forwarding IPv4 packets.

            TODO: Implement the forwarding steps, for example:
              - standard_metadata.egress_spec = port;
              - hdr.ethernet.dstAddr = dstAddr;
              - (optionally) set hdr.ethernet.srcAddr to the switch MAC for 'port'
              - adjust IPv4 TTL and checksums as needed
        */
        // 1. 出力ポートを設定（パケットをどのポートから送出するか）
        standard_metadata.egress_spec = port;

        // 2. Ethernet送信元MACアドレスを更新
        //    現在の宛先MAC（このスイッチのMAC）を送信元MACに設定
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;

        // 3. Ethernet宛先MACアドレスを次のホップのMACに書き換え
        //    (dstAddrはコントロールプレーンから渡される)
        hdr.ethernet.dstAddr = dstAddr;

        // 4. IPv4のTTL（Time To Live）を1減らす
        //    ルーターを1ホップ通過したことを示す
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    /*********************************************************************
     * LPM table for IPv4:
     *   - Matches on hdr.ipv4.dstAddr using longest-prefix match (lpm)
     *   - On hit, calls ipv4_forward with *action data* populated by the
     *     control plane when it installs the table entry.
     *********************************************************************/
    // IPv4ルーティングテーブル
    // LPM (Longest Prefix Match) を使用して宛先IPアドレスにマッチ
    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;  // 宛先IPアドレスで最長プレフィックスマッチ
                                     // 例: 10.0.1.0/24は10.0.1.1にマッチ
        }
        actions = {
            ipv4_forward;  // マッチした場合、パケットを転送
            drop;          // マッチしない場合、パケットを破棄
            NoAction;      // 何もしない（デフォルト）
        }
        size = 1024;                 // テーブルの最大エントリ数
        default_action = NoAction(); // デフォルトではマッチしなくても何もしない
    }

    apply {
        /* TODO: fix ingress control logic
         *  - Good practice: apply ipv4_lpm only when the IPv4 header is valid, e.g.:
         *      if (hdr.ipv4.isValid()) { ipv4_lpm.apply(); }
         *    This skeleton currently applies unconditionally for the exercise.
         */
        // IPv4ヘッダーが有効（パーサーで正しく抽出された）場合のみ、
        // LPMテーブルを適用してルーティング処理を実行
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();  // 宛先IPアドレスでLPM検索を実行
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
* Ingressパイプラインの後、パケットが出力ポートに送られる前に実行される  *
* キューイング、ミラーリング、ポストルーティング編集などに使用           *
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {
        // Egress処理をここに実装可能
        // 例: パケットのミラーリング、QoSマーキング、統計情報の収集など
    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
* Egressパイプラインの後、Deparserの前に実行される                       *
* パケット送出前にヘッダーのチェックサムを再計算する                     *
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {
        // IPv4ヘッダーのチェックサムを再計算
        // ヘッダーフィールドを変更した場合（例: TTLの減算）、
        // チェックサムも更新する必要がある
        update_checksum(
            hdr.ipv4.isValid(),  // IPv4ヘッダーが有効な場合のみ計算
            { hdr.ipv4.version,  // チェックサム計算に含めるフィールドのリスト
              hdr.ipv4.ihl,      // これらのフィールド全体でチェックサムを計算
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,    // 計算結果を格納するフィールド
            HashAlgorithm.csum16);   // 16ビットのインターネットチェックサムを使用
    }
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
* The deparser serializes headers back onto the packet in order.         *
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        /*
        Typical implementation (left as a TODO for learners):
            packet.emit(hdr.ethernet);
            packet.emit(hdr.ipv4);   // per P4_16 spec, emit appends a header
                                     // only if it is valid; no 'if' needed.
        */
        // ヘッダーをパケットに再構築（シリアライズ）
        // emit()は有効なヘッダーのみを出力するため、if文は不要
        packet.emit(hdr.ethernet);  // Ethernetヘッダーを最初に出力
        packet.emit(hdr.ipv4);      // IPv4ヘッダーを次に出力（有効な場合のみ）
    }
}

/*************************************************************************
***********************  S W I T C H  ***********************************
* V1Switchアーキテクチャのインスタンス化                                 *
* パケット処理パイプライン全体を定義する                                 *
*************************************************************************/

// V1Switchパイプラインのインスタンス化
// パケットは以下の順序で処理される:
// 1. MyParser(): パケットからヘッダーを抽出
// 2. MyVerifyChecksum(): 受信時のチェックサム検証
// 3. MyIngress(): Ingress処理（ルーティング判断など）
// 4. MyEgress(): Egress処理（出力ポート固有の処理）
// 5. MyComputeChecksum(): 送信時のチェックサム再計算
// 6. MyDeparser(): ヘッダーをパケットに再構築
V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(), // drop の場合は、これ以降実行されない
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
