import XCTest
@testable import PocketLocket

final class ImportParsersTests: XCTestCase {
    func testOFXParsing() {
        let ofx = """
        OFXHEADER:100
        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS>
        <CURDEF>USD
        <BANKACCTFROM><ACCTID>1234567890</BANKACCTFROM>
        <BANKTRANLIST>
        <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260115120000<TRNAMT>-42.50<FITID>abc123<NAME>Coffee Shop</STMTTRN>
        <STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20260116<TRNAMT>1500.00<FITID>def456<NAME>Paycheck</STMTTRN>
        </BANKTRANLIST>
        <LEDGERBAL><BALAMT>2500.00<DTASOF>20260116</LEDGERBAL>
        </STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """

        let statement = OFXParser.parse(ofx)
        XCTAssertEqual(statement.accountId, "1234567890")
        XCTAssertEqual(statement.ledgerBalance ?? 0, 2500, accuracy: 0.001)
        XCTAssertEqual(statement.transactions.count, 2)

        // OFX debit (-42.50) becomes app-spend (+42.50).
        let coffee = statement.transactions.first { $0.name == "Coffee Shop" }
        XCTAssertEqual(coffee?.amount ?? 0, 42.50, accuracy: 0.001)

        // OFX credit (+1500) becomes app-income (-1500).
        let paycheck = statement.transactions.first { $0.name == "Paycheck" }
        XCTAssertEqual(paycheck?.amount ?? 0, -1500, accuracy: 0.001)
    }

    func testCSVSingleAmountColumn() {
        let csv = """
        Date,Description,Amount
        2026-01-15,Coffee Shop,-42.50
        2026-01-16,Paycheck,1500.00
        """
        let rows = CSVParser.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].description, "Coffee Shop")
        XCTAssertEqual(rows[0].amount, 42.50, accuracy: 0.001) // spend
        XCTAssertEqual(rows[1].amount, -1500, accuracy: 0.001) // income
    }

    func testCSVDebitCreditColumns() {
        let csv = """
        Date,Description,Debit,Credit
        01/15/2026,Store,42.50,
        01/16/2026,Refund,,10.00
        """
        let rows = CSVParser.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].amount, 42.50, accuracy: 0.001) // debit = spend
        XCTAssertEqual(rows[1].amount, -10.0, accuracy: 0.001) // credit = income
    }
}
