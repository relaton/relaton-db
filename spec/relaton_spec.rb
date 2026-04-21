RSpec.describe Relaton::Db do
  before :each do |example|
    FileUtils.rm_rf %w(testcache testcache2)
    @db = Relaton::Db.new "testcache", "testcache2"
    Relaton.instance_variable_set :@configuration, nil

    if example.metadata[:vcr]
      require "relaton/index"
      allow_any_instance_of(Relaton::Index::Type)
        .to receive(:actual?).and_return(false)
      allow_any_instance_of(Relaton::Index::FileIO)
        .to receive(:check_file).and_return(nil)
    end
  end

  it "rejects an illegal reference prefix" do
    expect { @db.fetch("XYZ XYZ", nil, {}) }.to output(
      /\[relaton\] INFO: \(XYZ XYZ\) `XYZ XYZ` does not/,
    ).to_stderr_from_any_process
  end

  context "gets an ISO reference" do
    it "and caches it" do
      docid = Relaton::Bib::Docidentifier.new(content: "ISO 19115-1",
                                              type: "ISO")
      item = Relaton::Iso::ItemData.new(
        docid: [docid], fetched: Date.today.to_s,
      )
      expect(Relaton::Iso::Bibliography).to receive(:get)
        .with("ISO 19115-1", nil, {}).and_return item
      bib = @db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of Relaton::Iso::ItemData
      bib = @db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of Relaton::Iso::ItemData
    end

    it "with year in code" do
      VCR.use_cassette "iso_19133_2005" do
        bib = @db.fetch("ISO 19133:2005")
        expect(bib).to be_instance_of Relaton::Iso::ItemData
        xml = bib.to_xml
        expect(xml).to include 'id="ISO191332005"'
        expect(xml).to include 'type="standard"'
        testcache = Relaton::DbCache.new "testcache"
        expect(
          testcache.valid_entry?("ISO(ISO 19133:2005)", Date.today.year.to_s),
        ).to eq Date.today.year.to_s
      end
    end

    context "all parts" do
      it "implicity" do
        VCR.use_cassette "iso_19115_all_parts" do
          bib = @db.fetch("ISO 19115", nil, all_parts: true)
          expect(bib.docidentifier[0].content).to eq "ISO 19115 (all parts)"
        end
      end

      it "explicity" do
        VCR.use_cassette "iso_19115_all_parts" do
          bib = @db.fetch("ISO 19115 (all parts)")
          expect(bib.docidentifier[0].content).to eq "ISO 19115 (all parts)"
        end
      end
    end

    it "gets sn ISO/DIS reference" do
      VCR.use_cassette "iso_dis" do
        bib = @db.fetch "ISO/DIS 14460"
        expect(bib.docidentifier[0].content).to eq "ISO/DIS 14460"
      end
    end
  end

  context "IEC" do
    before do
      require "relaton/iec"
      docid = Relaton::Iec::Docidentifier.new(
        content: "IEC 60050-102:2007", type: "IEC",
      )
      item = Relaton::Iec::ItemData.new docidentifier: [docid]
      expect(Relaton::Iec::Bibliography).to receive(:get).with(
        "IEC 60050-102:2007", nil, {}
      ).and_return item
    end

    it "get by reference" do
      bib = @db.fetch "IEC 60050-102:2007"
      expect(bib.docidentifier[0].content).to eq "IEC 60050-102:2007"
    end

    it "get by URN" do
      bib = @db.fetch "urn:iec:std:iec:60050-102:2007:::"
      expect(bib.docidentifier[0].content).to eq "IEC 60050-102:2007"
    end
  end

  context "NIST references" do
    it "gets FISP" do
      require "relaton/nist"
      docid = Relaton::Bib::Docidentifier.new(content: "NIST FIPS 140",
                                              type: "NIST")
      item = Relaton::Nist::ItemData.new docidentifier: [docid]
      expect(Relaton::Nist::Bibliography).to receive(:get).with(
        "NIST FIPS 140", nil, {}
      ).and_return item
      bib = @db.fetch "NIST FIPS 140"
      expect(bib).to be_instance_of Relaton::Nist::ItemData
      expect(bib.docidentifier[0].content).to eq "NIST FIPS 140"
    end

    it "gets SP" do
      require "relaton/nist"
      docid = Relaton::Bib::Docidentifier.new(content: "NIST SP 800-38B",
                                              type: "NIST")
      item = Relaton::Nist::ItemData.new docidentifier: [docid]
      expect(Relaton::Nist::Bibliography).to receive(:get).with(
        "NIST SP 800-38B", nil, {}
      ).and_return item
      bib = @db.fetch "NIST SP 800-38B"
      expect(bib).to be_instance_of Relaton::Nist::ItemData
      expect(bib.docidentifier[0].content).to eq "NIST SP 800-38B"
    end
  end

  it "deals with a non-existant ISO reference" do
    VCR.use_cassette "iso_111111119115_1" do
      bib = @db.fetch("ISO 111111119115-1", nil, {})
      expect(bib).to be_nil
      expect(File.exist?("testcache")).to be true
      expect(File.exist?("testcache2")).to be true
      testcache = Relaton::DbCache.new "testcache"
      expect(testcache.fetched("ISO(ISO 111111119115-1)")).to eq Date.today.to_s
      expect(testcache["ISO(ISO 111111119115-1)"]).to include "not_found"
      testcache = Relaton::DbCache.new "testcache2"
      expect(testcache.fetched("ISO(ISO 111111119115-1)")).to eq Date.today.to_s
      expect(testcache["ISO(ISO 111111119115-1)"]).to include "not_found"
    end
  end

  it "list all elements as a serialization" do
    VCR.use_cassette "iso_19115_1_2", match_requests_on: [:path] do
      @db.fetch "ISO 19115-1", nil, {}
      @db.fetch "ISO 19115-2", nil, {}
    end
    # file = "spec/support/list_entries.xml"
    # File.write file, @db.to_xml unless File.exist? file
    docs = Nokogiri::XML @db.to_xml
    expect(docs.xpath("/documents/bibdata").size).to eq 2
  end

  it "save/load/delete entry" do
    @db.save_entry "test key", "test value"
    expect(@db.load_entry("test key")).to eq "test value"
    expect(@db.load_entry("not existed key")).to be_nil
    @db.save_entry "test key", nil
    expect(@db.load_entry("test key")).to be_nil
    testcache = Relaton::DbCache.new "testcache"
    testcache.delete("test_key")
    testcache2 = Relaton::DbCache.new "testcache2"
    testcache2.delete("test_key")
    expect(@db.load_entry("test key")).to be_nil
  end

  context "get GB reference" do
    it "and cache it" do
      VCR.use_cassette "gb_t_20223_2006" do
        bib = @db.fetch "CN(GB/T 20223)", "2006", {}
        expect(bib).to be_instance_of Relaton::Gb::ItemData
        expect(bib.to_xml(bibdata: true)).to include <<~XML
          <project-number origyr="2006">GB/T 20223-2006</project-number>
        XML
        expect(File.exist?("testcache")).to be true
        expect(File.exist?("testcache2")).to be true
        testcache = Relaton::DbCache.new "testcache"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number origyr="2006">GB/T 20223-2006</project-number>
        XML
        testcache = Relaton::DbCache.new "testcache2"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number origyr="2006">GB/T 20223-2006</project-number>
        XML
      end
    end

    it "with year" do
      VCR.use_cassette "gb_t_20223_2006" do
        bib = @db.fetch "CN(GB/T 20223-2006)", nil, {}
        expect(bib).to be_instance_of Relaton::Gb::ItemData
        expect(bib.to_xml(bibdata: true)).to include <<~XML
          <project-number origyr="2006">GB/T 20223-2006</project-number>
        XML
        expect(File.exist?("testcache")).to be true
        expect(File.exist?("testcache2")).to be true
        testcache = Relaton::DbCache.new "testcache"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number origyr="2006">GB/T 20223-2006</project-number>
        XML
        testcache = Relaton::DbCache.new "testcache2"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number origyr="2006">GB/T 20223-2006</project-number>
        XML
      end
    end
  end

  it "get RFC reference and cache it" do
    VCR.use_cassette "rfc_8341" do
      bib = @db.fetch "RFC 8341", nil, {}
      expect(bib).to be_instance_of Relaton::Ietf::ItemData
      expect(bib.to_xml).to match(
        /<bibitem id="RFC8341" type="standard" schema-version="v[\d.]+">/,
      )
      expect(File.exist?("testcache")).to be true
      expect(File.exist?("testcache2")).to be true
      testcache = Relaton::DbCache.new "testcache"
      expect(testcache["IETF(RFC 8341)"]).to include(
        '<docidentifier type="IETF" primary="true">RFC 8341</docidentifier>',
      )
      testcache = Relaton::DbCache.new "testcache2"
      expect(testcache["IETF(RFC 8341)"]).to include(
        '<docidentifier type="IETF" primary="true">RFC 8341</docidentifier>',
      )
    end
  end

  it "get OGC refrence and cache it" do
    cc_fr = /\.relaton\/ogc\/bibliography\.json/
    allow(File).to receive(:exist?).with(cc_fr).and_return false
    allow(File).to receive(:exist?).with(/etag\.txt/).and_return false
    expect(File).to receive(:exist?).and_call_original.at_least :once
    expect(File).to receive(:write).with(cc_fr, kind_of(String), kind_of(Hash))
      .at_most :once
    allow(File).to receive(:write).and_call_original
    VCR.use_cassette "ogc_19_025r1" do
      ogc_bib = "/Users/andrej/.relaton/ogc/bibliography.json"
      expect(File).to receive(:exist?).with(ogc_bib)
        .and_return(false).at_most :once
      ogc_etag = "/Users/andrej/.relaton/ogc/etag.txt"
      expect(File).to receive(:exist?).with(ogc_etag)
        .and_return(false).at_most :once
      allow(File).to receive(:exist?).and_call_original
      bib = @db.fetch "OGC 19-025r1", nil, {}
      expect(bib).to be_instance_of Relaton::Ogc::ItemData
    end
  end

  it "get Calconnect refrence and cache it" do
    VCR.use_cassette "cc_dir_10005_2019", match_requests_on: [:path] do
      bib = @db.fetch "CC/DIR 10005:2019", nil, {}
      expect(bib).to be_instance_of Relaton::Calconnect::ItemData
    end
  end

  it "get OMG reference" do
    VCR.use_cassette "omg_ami4ccm_1_0" do
      bib = @db.fetch "OMG AMI4CCM 1.0", nil, {}
      expect(bib).to be_instance_of Relaton::Omg::ItemData
    end
  end

  # it "get UN reference" do
  #   docid = RelatonBib::DocumentIdentifier.new(
  #     id: "UN TRADE/CEFACT/2004/32", type: "UN",
  #   )
  #   item = RelatonUn::UnBibliographicItem.new(
  #     docid: [docid],
  #     session: RelatonUn::Session.new(session_number: "1"),
  #   )
  #   expect(RelatonUn::UnBibliography).to receive(:get)
  #     .with("UN TRADE/CEFACT/2004/32", nil, {})
  #     .and_return item
  #   bib = @db.fetch "UN TRADE/CEFACT/2004/32", nil, {}
  #   expect(bib).to be_instance_of(
  #     RelatonUn::UnBibliographicItem,
  #   )
  #   expect(bib.docidentifier.first.id)
  #     .to eq "UN TRADE/CEFACT/2004/32"
  # end

  it "get W3C reference" do
    require "relaton/w3c"
    docid = Relaton::Bib::Docidentifier.new(
      content: "W3C REC-json-ld11-20200716", type: "W3C",
    )
    item = Relaton::W3c::ItemData.new docidentifier: [docid]
    expect(Relaton::W3c::Bibliography).to receive(:get).with(
      "W3C REC-json-ld11-20200716", nil, {}
    ).and_return item
    bib = @db.fetch "W3C REC-json-ld11-20200716", nil, {}
    expect(bib).to be_instance_of Relaton::W3c::ItemData
    expect(bib.docidentifier.first.content).to eq "W3C REC-json-ld11-20200716"
  end

  it "get CCSDS reference" do
    require "relaton/ccsds"
    docid = Relaton::Bib::Docidentifier.new content: "CCSDS 230.2-G-1",
                                            type: "CCSDS"
    item = Relaton::Ccsds::ItemData.new docidentifier: [docid]
    expect(Relaton::Ccsds::Bibliography).to receive(:get).with(
      "CCSDS 230.2-G-1", nil, {}
    ).and_return item
    bib = @db.fetch "CCSDS 230.2-G-1", nil, {}
    expect(bib).to be_instance_of Relaton::Ccsds::ItemData
    expect(bib.docidentifier.first.content).to eq "CCSDS 230.2-G-1"
  end

  it "get IEEE reference", vcr: "ieee_528_2019" do
    bib = @db.fetch "IEEE Std 528-2019"
    expect(bib).to be_instance_of Relaton::Ieee::ItemData
  end

  it "get IHO reference" do
    require "relaton/iho"
    docid = Relaton::Bib::Docidentifier.new(content: "IHO B-11", type: "IHO")
    item = Relaton::Iho::ItemData.new docidentifier: [docid]
    expect(Relaton::Iho::Bibliography).to receive(:get).with("IHO B-11", nil,
                                                             {}).and_return item
    bib = @db.fetch "IHO B-11"
    expect(bib).to be_instance_of Relaton::Iho::ItemData
    expect(bib.docidentifier.first.content).to eq "IHO B-11"
  end

  it "get ECMA reference" do
    VCR.use_cassette "ecma_6" do
      bib = @db.fetch "ECMA-6"
      expect(bib).to be_instance_of Relaton::Ecma::ItemData
    end
  end

  it "get CIE reference" do
    VCR.use_cassette "cie_001_1980" do
      bib = @db.fetch "CIE 001-1980"
      expect(bib).to be_instance_of Relaton::Cie::ItemData
    end
  end

  it "get BSI reference" do
    require "relaton/bsi"
    docid = Relaton::Bib::Docidentifier.new(content: "BSI BS EN ISO 8848",
                                            type: "BSI")
    item = Relaton::Bsi::ItemData.new docidentifier: [docid]
    expect(Relaton::Bsi::Bibliography).to receive(:get).with(
      "BSI BS EN ISO 8848", nil, {}
    ).and_return item
    bib = @db.fetch "BSI BS EN ISO 8848"
    expect(bib).to be_instance_of Relaton::Bsi::ItemData
  end

  it "get CEN reference" do
    VCR.use_cassette "en_10160_1999" do
      bib = @db.fetch "EN 10160:1999"
      expect(bib).to be_instance_of Relaton::Cen::ItemData
    end
  end

  it "get IANA reference" do
    require "relaton/iana"
    docid = Relaton::Bib::Docidentifier.new(
      content: "IANA service-names-port-numbers", type: "IANA",
    )
    item = Relaton::Iana::ItemData.new docidentifier: [docid]
    expect(Relaton::Iana::Bibliography).to receive(:get).with(
      "IANA service-names-port-numbers", nil, {}
    ).and_return item
    bib = @db.fetch "IANA service-names-port-numbers"
    expect(bib).to be_instance_of Relaton::Iana::ItemData
  end

  it "get 3GPP reference" do
    VCR.use_cassette "3gpp_tr_00_01u_umts_3_0_0" do
      bib = @db.fetch "3GPP TR 00.01U:UMTS/3.0.0"
      expect(bib).to be_instance_of Relaton::ThreeGpp::ItemData
    end
  end

  it "get OASIS reference" do
    require "relaton/oasis"
    docid = Relaton::Bib::Docidentifier.new(
      content: "OASIS amqp-core-types-v1.0-Pt1", type: "OASIS",
    )
    item = Relaton::Oasis::ItemData.new docidentifier: [docid]
    expect(Relaton::Oasis::Bibliography).to receive(:get).with(
      "OASIS amqp-core-types-v1.0-Pt1", nil, {}
    ).and_return item
    bib = @db.fetch "OASIS amqp-core-types-v1.0-Pt1"
    expect(bib).to be_instance_of Relaton::Oasis::ItemData
  end

  it "get BIPM reference" do
    require "relaton/bipm"
    docid = Relaton::Bib::Docidentifier.new(
      content: "BIPM Metrologia 29 6 373", type: "BIPM",
    )
    item = Relaton::Bipm::ItemData.new docidentifier: [docid]
    expect(Relaton::Bipm::Bibliography).to receive(:get).with(
      "BIPM Metrologia 29 6 373", nil, {}
    ).and_return item
    bib = @db.fetch "BIPM Metrologia 29 6 373"
    expect(bib).to be_instance_of Relaton::Bipm::ItemData
    expect(bib.docidentifier.first.content).to eq "BIPM Metrologia 29 6 373"
  end

  it "get DOI reference", vcr: "doi_10_6028_nist_ir_8245" do
    bib = @db.fetch "doi:10.6028/nist.ir.8245"
    expect(bib).to be_instance_of Relaton::Bib::ItemData
  end

  it "get JIS reference" do
    require "relaton/jis"
    docid = Relaton::Bib::Docidentifier.new(content: "JIS X 0001", type: "JIS")
    item = Relaton::Jis::ItemData.new docidentifier: [docid]
    expect(Relaton::Jis::Bibliography).to receive(:get).with("JIS X 0001", nil,
                                                             {}).and_return item
    bib = @db.fetch "JIS X 0001"
    expect(bib).to be_instance_of Relaton::Jis::ItemData
    expect(bib.docidentifier.first.content).to eq "JIS X 0001"
  end

  it "get XSF reference" do
    require "relaton/xsf"
    docid = Relaton::Bib::Docidentifier.new(content: "XEP 0001", type: "XSF")
    item = Relaton::Bib::ItemData.new docidentifier: [docid]
    expect(Relaton::Xsf::Bibliography).to receive(:get).with("XEP 0001", nil,
                                                             {}).and_return item
    bib = @db.fetch "XEP 0001"
    expect(bib).to be_instance_of Relaton::Xsf::ItemData
    expect(bib.docidentifier.first.content).to eq "XEP 0001"
  end

  it "get ETSI reference" do
    require "relaton/etsi"
    docid = Relaton::Bib::Docidentifier.new(content: "ETSI EN 300 175-8",
                                            type: "ETSI")
    item = Relaton::Etsi::ItemData.new docidentifier: [docid]
    expect(Relaton::Etsi::Bibliography).to receive(:get).with(
      "ETSI EN 300 175-8", nil, {}
    ).and_return item
    bib = @db.fetch "ETSI EN 300 175-8"
    expect(bib).to be_instance_of Relaton::Etsi::ItemData
    expect(bib.docidentifier.first.content).to eq "ETSI EN 300 175-8"
  end

  it "get ISBN reference" do
    require "relaton/isbn"
    docid = Relaton::Bib::Docidentifier.new(content: "ISBN 978-0-580-50101-4",
                                            type: "ISBN")
    item = Relaton::Bib::ItemData.new docidentifier: [docid]
    expect(Relaton::Isbn::OpenLibrary).to receive(:get).with(
      "ISBN 978-0-580-50101-4", nil, {}
    ).and_return item
    bib = @db.fetch "ISBN 978-0-580-50101-4"
    expect(bib).to be_instance_of Relaton::Bib::ItemData
    expect(bib.docidentifier.first.content).to eq "ISBN 978-0-580-50101-4"
  end

  it "get PLATEAU reference" do
    require "relaton/plateau"
    docid = Relaton::Bib::Docidentifier.new(content: "PLATEAU Hanbook #01",
                                            type: "PLATEAU")
    item = Relaton::Plateau::ItemData.new docidentifier: [docid]
    expect(Relaton::Plateau::Bibliography).to receive(:get).with(
      "PLATEAU Hanbook #01", nil, {}
    ).and_return item
    bib = @db.fetch "PLATEAU Hanbook #01"
    expect(bib).to be_instance_of Relaton::Plateau::ItemData
    expect(bib.docidentifier.first.content).to eq "PLATEAU Hanbook #01"
  end

  context "get combined documents" do
    context "ISO" do
      it "included" do
        VCR.use_cassette "iso_combined_included" do
          bib = @db.fetch "ISO 19115-1:2014 + Amd 1"
          expect(bib.docidentifier[0].content)
            .to eq "ISO 19115-1:2014 + Amd 1"
          expect(bib.relation[0].type).to eq "updates"
          rel0 = bib.relation[0].bibitem
          expect(rel0.docidentifier[0].content)
            .to eq "ISO 19115-1:2014"
          expect(bib.relation[1].type).to eq "derivedFrom"
          expect(bib.relation[1].description).to be_nil
          rel1 = bib.relation[1].bibitem
          expect(rel1.docidentifier[0].content)
            .to eq "ISO 19115-1:2014/Amd 1:2018"
        end
      end

      it "applied" do
        VCR.use_cassette "iso_combined_applied" do
          bib = @db.fetch "ISO 19115-1:2014, Amd 1"
          expect(bib.docidentifier[0].content)
            .to eq "ISO 19115-1:2014, Amd 1"
          expect(bib.relation[0].type).to eq "updates"
          rel0 = bib.relation[0].bibitem
          expect(rel0.docidentifier[0].content)
            .to eq "ISO 19115-1:2014"
          expect(bib.relation[1].type).to eq "complements"
          expect(bib.relation[1].description.content)
            .to eq "amendment"
          rel1 = bib.relation[1].bibitem
          expect(rel1.docidentifier[0].content)
            .to eq "ISO 19115-1:2014/Amd 1:2018"
        end
      end
    end

    context "IEC" do
      it "included" do
        require "relaton/iec"
        docid = Relaton::Iec::Docidentifier.new(
          content: "IEC 60027-1", type: "IEC",
        )
        item = Relaton::Iec::ItemData.new(
          docidentifier: [docid],
        )
        expect(Relaton::Iec::Bibliography).to receive(:get)
          .with("IEC 60027-1", nil, {}).and_return item
        docid1 = Relaton::Iec::Docidentifier.new(
          content: "IEC 60027-1/AMD1:1997", type: "IEC",
        )
        item1 = Relaton::Iec::ItemData.new(
          docidentifier: [docid1],
        )
        expect(Relaton::Iec::Bibliography).to receive(:get)
          .with("IEC 60027-1/Amd 1", nil, {})
          .and_return item1
        docid2 = Relaton::Iec::Docidentifier.new(
          content: "IEC 60027-1/AMD2:2005", type: "IEC",
        )
        item2 = Relaton::Iec::ItemData.new(
          docidentifier: [docid2],
        )
        expect(Relaton::Iec::Bibliography).to receive(:get)
          .with("IEC 60027-1/Amd 2", nil, {})
          .and_return item2
        bib = @db.fetch "IEC 60027-1, Amd 1, Amd 2"
        expect(bib.docidentifier[0].content)
          .to eq "IEC 60027-1, Amd 1, Amd 2"
        expect(bib.relation[0].type).to eq "updates"
        rel0 = bib.relation[0].bibitem
        expect(rel0.docidentifier[0].content)
          .to eq "IEC 60027-1"
        expect(bib.relation[1].type).to eq "complements"
        expect(bib.relation[1].description.content)
          .to eq "amendment"
        rel1 = bib.relation[1].bibitem
        expect(rel1.docidentifier[0].content)
          .to eq "IEC 60027-1/AMD1:1997"
        expect(bib.relation[2].type).to eq "complements"
        expect(bib.relation[2].description.content)
          .to eq "amendment"
        rel2 = bib.relation[2].bibitem
        expect(rel2.docidentifier[0].content)
          .to eq "IEC 60027-1/AMD2:2005"
      end
    end

    context "ITU" do
      it "included" do
        require "relaton/itu"
        docid = Relaton::Bib::Docidentifier.new(content: "ITU-T G.989.2",
                                                type: "ITU")
        org = Relaton::Bib::Organization.new(
          name: [Relaton::Bib::TypedLocalizedString.new(
            content: "International Telecommunication Union",
          )],
          abbreviation: Relaton::Bib::LocalizedString.new(content: "ITU-T"),
          subdivision: [Relaton::Bib::Subdivision.new(
            type: "technical-committee",
            subtype: "study-group",
            name: [Relaton::Bib::TypedLocalizedString.new(content: "Group")],
          )],
        )
        role = Relaton::Bib::Contributor::Role.new(
          type: "author",
          description: [Relaton::Bib::LocalizedMarkedUpString.new(
            content: "committee",
          )],
        )
        contrib = Relaton::Bib::Contributor.new(organization: org, role: [role])
        item = Relaton::Itu::ItemData.new(
          docidentifier: [docid], contributor: [contrib],
        )
        expect(Relaton::Itu::Bibliography).to receive(:get).with(
          "ITU-T G.989.2", nil, {}
        ).and_return item
        docid1 = Relaton::Bib::Docidentifier.new(
          content: "ITU-T G.989.2 Amd 1", type: "ITU",
        )
        item1 = Relaton::Itu::ItemData.new(
          docidentifier: [docid1], contributor: [contrib],
        )
        expect(Relaton::Itu::Bibliography).to receive(:get).with(
          "ITU-T G.989.2 Amd 1", nil, {}
        ).and_return item1
        docid2 = Relaton::Bib::Docidentifier.new(
          content: "ITU-T G.989.2 Amd 2", type: "ITU",
        )
        item2 = Relaton::Itu::ItemData.new(
          docidentifier: [docid2], contributor: [contrib],
        )
        expect(Relaton::Itu::Bibliography).to receive(:get).with(
          "ITU-T G.989.2 Amd 2", nil, {}
        ).and_return item2
        bib = @db.fetch "ITU-T G.989.2, Amd 1, Amd 2"
        expect(bib.docidentifier[0].content)
          .to eq "ITU-T G.989.2, Amd 1, Amd 2"
        expect(bib.relation[0].type).to eq "updates"
        rel0 = bib.relation[0].bibitem
        expect(rel0.docidentifier[0].content)
          .to eq "ITU-T G.989.2"
        expect(bib.relation[1].type).to eq "complements"
        expect(bib.relation[1].description.content)
          .to eq "amendment"
        rel1 = bib.relation[1].bibitem
        expect(rel1.docidentifier[0].content)
          .to eq "ITU-T G.989.2 Amd 1"
        expect(bib.relation[2].type).to eq "complements"
        expect(bib.relation[2].description.content)
          .to eq "amendment"
        rel2 = bib.relation[2].bibitem
        expect(rel2.docidentifier[0].content)
          .to eq "ITU-T G.989.2 Amd 2"
      end
    end

    context "NIST" do
      it "included" do
        # VCR.use_cassette "nist_combined_included" do
        require "relaton/nist"
        doci = Relaton::Bib::Docidentifier.new(content: "SP 800-38A",
                                               type: "NIST")
        item = Relaton::Nist::ItemData.new docidentifier: [doci]
        expect(Relaton::Nist::Bibliography).to receive(:get).with(
          "NIST SP 800-38A", nil, {}
        ).and_return item
        docid1 = Relaton::Bib::Docidentifier.new(content: "SP 800-38A-Add",
                                                 type: "NIST")
        item1 = Relaton::Nist::ItemData.new docidentifier: [docid1]
        expect(Relaton::Nist::Bibliography).to receive(:get).with(
          "NIST SP 800-38A/Add", nil, {}
        ).and_return item1
        bib = @db.fetch "NIST SP 800-38A, Add"
        expect(bib.docidentifier[0].content).to eq "NIST SP 800-38A, Add"
        expect(bib.relation[0].type).to eq "updates"
        rel0 = bib.relation[0].bibitem
        expect(rel0.docidentifier[0].content)
          .to eq "SP 800-38A"
        expect(bib.relation[1].type).to eq "complements"
        expect(bib.relation[1].description.content)
          .to eq "amendment"
        rel1 = bib.relation[1].bibitem
        expect(rel1.docidentifier[0].content)
          .to eq "SP 800-38A-Add"
        # end
      end
    end
  end

  context "version control" do
    before(:each) do
      @db.save_entry "iso(test_key)",
                     "<bibitem><title>test_value</title></bibitem>"
    end

    it "shoudn't clear cache if version isn't changed" do
      testcache = @db.instance_variable_get :@db
      expect(testcache.all).to be_any
      testcache = @db.instance_variable_get :@local_db
      expect(testcache.all).to be_any
    end

    it "should clear cache if version is changed" do
      expect(File.read("testcache/iso/version",
                       encoding: "UTF-8")).not_to eq "new_version"
      expect(File.read("testcache2/iso/version",
                       encoding: "UTF-8")).not_to eq "new_version"
      processor = double "processor", short: :relaton_iso
      expect(processor).to receive(:grammar_hash)
        .and_return("new_version").exactly(2).times
      expect(Relaton::Registry.instance)
        .to receive(:by_type)
        .and_return(processor).exactly(2).times
      Relaton::Db.new "testcache", "testcache2"
      expect(File.exist?("testcache/iso/version")).to eq false
      expect(File.exist?("testcache2/iso/version")).to eq false
    end
  end

  context "api.relaton.org" do
    before(:each) do
      Relaton.configure do |config|
        config.use_api = true
        # config.api_host = "http://0.0.0.0:9292"
      end
    end

    after(:each) do
      Relaton.configure do |config|
        config.use_api = false
      end
    end

    it "get document" do
      VCR.use_cassette "api_relaton_org" do
        bib = @db.fetch "ISO 19115-2", "2019"
        expect(bib).to be_instance_of Relaton::Iso::ItemData
      end
    end

    it "if unavailable then get document directly" do
      expect(Net::HTTP).to receive(:get_response)
        .and_wrap_original do |m, *args|
        raise Errno::ECONNREFUSED if args[0].host == "api.relaton.org"

        m.call(*args)
      end.at_least :once
      VCR.use_cassette "api_relaton_org_unavailable" do
        bib = @db.fetch "ISO 19115-2", "2019"
        expect(bib).to be_instance_of Relaton::Iso::ItemData
      end
    end
  end
end
