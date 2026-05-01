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
      /\[relaton\] INFO: \(XYZ XYZ\) `XYZ XYZ` does not have a recognised prefix/,
    ).to_stderr_from_any_process
  end

  context "gets an ISO reference" do
    it "and caches it" do
      docid = RelatonBib::DocumentIdentifier.new(id: "ISO 19115-1", type: "ISO")
      item = RelatonIsoBib::IsoBibliographicItem.new docid: [docid], fetched: Date.today.to_s
      expect(RelatonIso::IsoBibliography).to receive(:get).with("ISO 19115-1", nil, {}).and_return item
      bib = @db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      bib = @db.fetch("ISO 19115-1", nil, {})
      expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
    end

    it "with year in code" do
      VCR.use_cassette "iso_19133_2005" do
        bib = @db.fetch("ISO 19133:2005")
        expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
        xml = bib.to_xml
        expect(xml).to include 'id="ISO19133-2005"'
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
          expect(bib.docidentifier[0].id).to eq "ISO 19115 (all parts)"
        end
      end

      it "explicity" do
        VCR.use_cassette "iso_19115_all_parts" do
          bib = @db.fetch("ISO 19115 (all parts)")
          expect(bib.docidentifier[0].id).to eq "ISO 19115 (all parts)"
        end
      end
    end

    it "gets sn ISO/DIS reference" do
      VCR.use_cassette "iso_dis" do
        bib = @db.fetch "ISO/DIS 14460"
        expect(bib.docidentifier[0].id).to eq "ISO/DIS 14460"
      end
    end
  end

  context "IEC" do
    before do
      require "relaton_iec"
      docid = RelatonBib::DocumentIdentifier.new(id: "IEC 60050-102:2007", type: "IEC")
      item = RelatonIec::IecBibliographicItem.new docid: [docid]
      expect(RelatonIec::IecBibliography).to receive(:get).with("IEC 60050-102:2007", nil, {}).and_return item
    end

    it "get by reference" do
      bib = @db.fetch "IEC 60050-102:2007"
      expect(bib.docidentifier[0].id).to eq "IEC 60050-102:2007"
    end

    it "get by URN" do
      bib = @db.fetch "urn:iec:std:iec:60050-102:2007:::"
      expect(bib.docidentifier[0].id).to eq "IEC 60050-102:2007"
    end
  end

  context "NIST references" do
    it "gets FISP" do
      docid = RelatonBib::DocumentIdentifier.new(id: "NIST FIPS 140", type: "NIST")
      item = RelatonNist::NistBibliographicItem.new docid: [docid]
      expect(RelatonNist::NistBibliography).to receive(:get).with("NIST FIPS 140", nil, {}).and_return item
      bib = @db.fetch "NIST FIPS 140"
      expect(bib).to be_instance_of RelatonNist::NistBibliographicItem
      expect(bib.docidentifier[0].id).to eq "NIST FIPS 140"
    end

    it "gets SP" do
      docid = RelatonBib::DocumentIdentifier.new(id: "NIST SP 800-38B", type: "NIST")
      item = RelatonNist::NistBibliographicItem.new docid: [docid]
      expect(RelatonNist::NistBibliography).to receive(:get).with("NIST SP 800-38B", nil, {}).and_return item
      bib = @db.fetch "NIST SP 800-38B"
      expect(bib).to be_instance_of RelatonNist::NistBibliographicItem
      expect(bib.docidentifier[0].id).to eq "NIST SP 800-38B"
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
        expect(bib).to be_instance_of RelatonGb::GbBibliographicItem
        expect(bib.to_xml(bibdata: true)).to include <<~XML
          <project-number>GB/T 20223</project-number>
        XML
        expect(File.exist?("testcache")).to be true
        expect(File.exist?("testcache2")).to be true
        testcache = Relaton::DbCache.new "testcache"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number>GB/T 20223</project-number>
        XML
        testcache = Relaton::DbCache.new "testcache2"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number>GB/T 20223</project-number>
        XML
      end
    end

    it "with year" do
      VCR.use_cassette "gb_t_20223_2006" do
        bib = @db.fetch "CN(GB/T 20223-2006)", nil, {}
        expect(bib).to be_instance_of RelatonGb::GbBibliographicItem
        expect(bib.to_xml(bibdata: true)).to include <<~XML
          <project-number>GB/T 20223</project-number>
        XML
        expect(File.exist?("testcache")).to be true
        expect(File.exist?("testcache2")).to be true
        testcache = Relaton::DbCache.new "testcache"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number>GB/T 20223</project-number>
        XML
        testcache = Relaton::DbCache.new "testcache2"
        expect(testcache["CN(GB/T 20223-2006)"]).to include <<~XML
          <project-number>GB/T 20223</project-number>
        XML
      end
    end
  end

  it "get RFC reference and cache it" do
    VCR.use_cassette "rfc_8341" do
      bib = @db.fetch "RFC 8341", nil, {}
      expect(bib).to be_instance_of RelatonIetf::IetfBibliographicItem
      expect(bib.to_xml).to match(/<bibitem id="RFC8341" type="standard" schema-version="v[\d.]+">/)
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
      expect(File).to receive(:exist?).with("/Users/andrej/.relaton/ogc/bibliography.json").and_return(false).at_most :once
      expect(File).to receive(:exist?).with("/Users/andrej/.relaton/ogc/etag.txt").and_return(false).at_most :once
      allow(File).to receive(:exist?).and_call_original
      bib = @db.fetch "OGC 19-025r1", nil, {}
      expect(bib).to be_instance_of RelatonOgc::OgcBibliographicItem
    end
  end

  it "get Calconnect refrence and cache it" do
    VCR.use_cassette "cc_dir_10005_2019", match_requests_on: [:path] do
      bib = @db.fetch "CC/DIR 10005:2019", nil, {}
      expect(bib).to be_instance_of RelatonCalconnect::CcBibliographicItem
    end
  end

  it "get OMG reference" do
    VCR.use_cassette "omg_ami4ccm_1_0" do
      bib = @db.fetch "OMG AMI4CCM 1.0", nil, {}
      expect(bib).to be_instance_of RelatonOmg::OmgBibliographicItem
    end
  end

  # it "get UN reference" do
  #   docid = RelatonBib::DocumentIdentifier.new(id: "UN TRADE/CEFACT/2004/32", type: "UN")
  #   item = RelatonUn::UnBibliographicItem.new docid: [docid], session: RelatonUn::Session.new(session_number: "1")
  #   expect(RelatonUn::UnBibliography).to receive(:get).with("UN TRADE/CEFACT/2004/32", nil, {}).and_return item
  #   bib = @db.fetch "UN TRADE/CEFACT/2004/32", nil, {}
  #   expect(bib).to be_instance_of RelatonUn::UnBibliographicItem
  #   expect(bib.docidentifier.first.id).to eq "UN TRADE/CEFACT/2004/32"
  # end

  it "get W3C reference" do
    require "relaton_w3c"
    docid = RelatonBib::DocumentIdentifier.new(id: "W3C REC-json-ld11-20200716", type: "W3C")
    item = RelatonW3c::W3cBibliographicItem.new docid: [docid]
    expect(RelatonW3c::W3cBibliography).to receive(:get).with("W3C REC-json-ld11-20200716", nil, {}).and_return item
    bib = @db.fetch "W3C REC-json-ld11-20200716", nil, {}
    expect(bib).to be_instance_of RelatonW3c::W3cBibliographicItem
    expect(bib.docidentifier.first.id).to eq "W3C REC-json-ld11-20200716"
  end

  it "get CCSDS reference" do
    require "relaton_ccsds"
    docid = RelatonBib::DocumentIdentifier.new id: "CCSDS 230.2-G-1", type: "CCSDS"
    item = RelatonCcsds::BibliographicItem.new docid: [docid]
    expect(RelatonCcsds::Bibliography).to receive(:get).with("CCSDS 230.2-G-1", nil, {}).and_return item
    bib = @db.fetch "CCSDS 230.2-G-1", nil, {}
    expect(bib).to be_instance_of RelatonCcsds::BibliographicItem
    expect(bib.docidentifier.first.id).to eq "CCSDS 230.2-G-1"
  end

  it "get IEEE reference", vcr: "ieee_528_2019" do
    bib = @db.fetch "IEEE Std 528-2019"
    expect(bib).to be_instance_of RelatonIeee::IeeeBibliographicItem
  end

  it "get IHO reference" do
    require "relaton_iho"
    docid = RelatonBib::DocumentIdentifier.new(id: "IHO B-11", type: "IHO")
    item = RelatonIho::IhoBibliographicItem.new docid: [docid]
    expect(RelatonIho::IhoBibliography).to receive(:get).with("IHO B-11", nil, {}).and_return item
    bib = @db.fetch "IHO B-11"
    expect(bib).to be_instance_of RelatonIho::IhoBibliographicItem
    expect(bib.docidentifier.first.id).to eq "IHO B-11"
  end

  it "get ECMA reference" do
    VCR.use_cassette "ecma_6" do
      bib = @db.fetch "ECMA-6"
      expect(bib).to be_instance_of RelatonEcma::BibliographicItem
    end
  end

  it "get CIE reference" do
    VCR.use_cassette "cie_001_1980" do
      bib = @db.fetch "CIE 001-1980"
      expect(bib).to be_instance_of RelatonCie::BibliographicItem
    end
  end

  it "get BSI reference" do
    require "relaton_bsi"
    docid = RelatonBib::DocumentIdentifier.new(id: "BSI BS EN ISO 8848", type: "BSI")
    item = RelatonBsi::BsiBibliographicItem.new docid: [docid]
    expect(RelatonBsi::BsiBibliography).to receive(:get).with("BSI BS EN ISO 8848", nil, {}).and_return item
    bib = @db.fetch "BSI BS EN ISO 8848"
    expect(bib).to be_instance_of RelatonBsi::BsiBibliographicItem
  end

  it "get CEN reference" do
    VCR.use_cassette "en_10160_1999" do
      bib = @db.fetch "EN 10160:1999"
      expect(bib).to be_instance_of RelatonCen::BibliographicItem
    end
  end

  it "get IANA reference" do
    require "relaton_iana"
    docid = RelatonBib::DocumentIdentifier.new(id: "IANA service-names-port-numbers", type: "IANA")
    item = RelatonIana::IanaBibliographicItem.new docid: [docid]
    expect(RelatonIana::IanaBibliography).to receive(:get).with("IANA service-names-port-numbers", nil, {}).and_return item
    bib = @db.fetch "IANA service-names-port-numbers"
    expect(bib).to be_instance_of RelatonIana::IanaBibliographicItem
  end

  it "get 3GPP reference" do
    VCR.use_cassette "3gpp_tr_00_01u_umts_3_0_0" do
      bib = @db.fetch "3GPP TR 00.01U:UMTS/3.0.0"
      expect(bib).to be_instance_of Relaton3gpp::BibliographicItem
    end
  end

  it "get OASIS reference" do
    require "relaton_oasis"
    docid = RelatonBib::DocumentIdentifier.new(id: "OASIS amqp-core-types-v1.0-Pt1", type: "OASIS")
    item = RelatonOasis::OasisBibliographicItem.new docid: [docid]
    expect(RelatonOasis::OasisBibliography).to receive(:get).with("OASIS amqp-core-types-v1.0-Pt1", nil, {}).and_return item
    bib = @db.fetch "OASIS amqp-core-types-v1.0-Pt1"
    expect(bib).to be_instance_of RelatonOasis::OasisBibliographicItem
  end

  it "get BIPM reference" do
    require "relaton_bipm"
    docid = RelatonBib::DocumentIdentifier.new(id: "BIPM Metrologia 29 6 373", type: "BIPM")
    item = RelatonBipm::BipmBibliographicItem.new docid: [docid]
    expect(RelatonBipm::BipmBibliography).to receive(:get).with("BIPM Metrologia 29 6 373", nil, {}).and_return item
    bib = @db.fetch "BIPM Metrologia 29 6 373"
    expect(bib).to be_instance_of RelatonBipm::BipmBibliographicItem
    expect(bib.docidentifier.first.id).to eq "BIPM Metrologia 29 6 373"
  end

  it "get DOI reference", vcr: "doi_10_6028_nist_ir_8245" do
    bib = @db.fetch "doi:10.6028/nist.ir.8245"
    expect(bib).to be_instance_of RelatonBib::BibliographicItem
  end

  it "get JIS reference" do
    require "relaton_jis"
    docid = RelatonBib::DocumentIdentifier.new(id: "JIS X 0001", type: "JIS")
    item = RelatonJis::BibliographicItem.new docid: [docid]
    expect(RelatonJis::Bibliography).to receive(:get).with("JIS X 0001", nil, {}).and_return item
    bib = @db.fetch "JIS X 0001"
    expect(bib).to be_instance_of RelatonJis::BibliographicItem
    expect(bib.docidentifier.first.id).to eq "JIS X 0001"
  end

  it "get XSF reference" do
    require "relaton_xsf"
    docid = RelatonBib::DocumentIdentifier.new(id: "XEP 0001", type: "XSF")
    item = RelatonXsf::BibliographicItem.new docid: [docid]
    expect(RelatonXsf::Bibliography).to receive(:get).with("XEP 0001", nil, {}).and_return item
    bib = @db.fetch "XEP 0001"
    expect(bib).to be_instance_of RelatonXsf::BibliographicItem
    expect(bib.docidentifier.first.id).to eq "XEP 0001"
  end

  it "get ETSI reference" do
    require "relaton_etsi"
    docid = RelatonBib::DocumentIdentifier.new(id: "ETSI EN 300 175-8", type: "ETSI")
    item = RelatonEtsi::BibliographicItem.new docid: [docid]
    expect(RelatonEtsi::Bibliography).to receive(:get).with("ETSI EN 300 175-8", nil, {}).and_return item
    bib = @db.fetch "ETSI EN 300 175-8"
    expect(bib).to be_instance_of RelatonEtsi::BibliographicItem
    expect(bib.docidentifier.first.id).to eq "ETSI EN 300 175-8"
  end

  it "get ISBN reference" do
    require "relaton_isbn"
    docid = RelatonBib::DocumentIdentifier.new(id: "ISBN 978-0-580-50101-4", type: "ISBN")
    item = RelatonBib::BibliographicItem.new docid: [docid]
    expect(RelatonIsbn::OpenLibrary).to receive(:get).with("ISBN 978-0-580-50101-4", nil, {}).and_return item
    bib = @db.fetch "ISBN 978-0-580-50101-4"
    expect(bib).to be_instance_of RelatonBib::BibliographicItem
    expect(bib.docidentifier.first.id).to eq "ISBN 978-0-580-50101-4"
  end

  it "get PLATEAU reference" do
    require "relaton/plateau"
    docid = RelatonBib::DocumentIdentifier.new(id: "PLATEAU Hanbook #01", type: "PLATEAU")
    item = Relaton::Plateau::BibItem.new docid: [docid]
    expect(Relaton::Plateau::Bibliography).to receive(:get).with("PLATEAU Hanbook #01", nil, {}).and_return item
    bib = @db.fetch "PLATEAU Hanbook #01"
    expect(bib).to be_instance_of Relaton::Plateau::BibItem
    expect(bib.docidentifier.first.id).to eq "PLATEAU Hanbook #01"
  end

  context "get combined documents" do
    context "ISO" do
      it "included" do
        VCR.use_cassette "iso_combined_included" do
          bib = @db.fetch "ISO 19115-1:2014 + Amd 1"
          expect(bib.docidentifier[0].id).to eq "ISO 19115-1:2014 + Amd 1"
          expect(bib.relation[0].type).to eq "updates"
          expect(bib.relation[0].bibitem.docidentifier[0].id).to eq "ISO 19115-1:2014"
          expect(bib.relation[1].type).to eq "derivedFrom"
          expect(bib.relation[1].description).to be_nil
          expect(bib.relation[1].bibitem.docidentifier[0].id).to eq "ISO 19115-1:2014/Amd 1:2018"
        end
      end

      it "applied" do
        VCR.use_cassette "iso_combined_applied" do
          bib = @db.fetch "ISO 19115-1:2014, Amd 1"
          expect(bib.docidentifier[0].id).to eq "ISO 19115-1:2014, Amd 1"
          expect(bib.relation[0].type).to eq "updates"
          expect(bib.relation[0].bibitem.docidentifier[0].id).to eq "ISO 19115-1:2014"
          expect(bib.relation[1].type).to eq "complements"
          expect(bib.relation[1].description.content).to eq "amendment"
          expect(bib.relation[1].bibitem.docidentifier[0].id).to eq "ISO 19115-1:2014/Amd 1:2018"
        end
      end
    end

    context "IEC" do
      it "included" do
        item = RelatonIec::IecBibliographicItem.new docid: [RelatonBib::DocumentIdentifier.new(id: "IEC 60027-1", type: "IEC")]
        expect(RelatonIec::IecBibliography).to receive(:get).with("IEC 60027-1", nil, {}).and_return item
        item1 = RelatonIec::IecBibliographicItem.new docid: [RelatonBib::DocumentIdentifier.new(id: "IEC 60027-1/AMD1:1997", type: "IEC")]
        expect(RelatonIec::IecBibliography).to receive(:get).with("IEC 60027-1/Amd 1", nil, {}).and_return item1
        item2 = RelatonIec::IecBibliographicItem.new docid: [RelatonBib::DocumentIdentifier.new(id: "IEC 60027-1/AMD2:2005", type: "IEC")]
        expect(RelatonIec::IecBibliography).to receive(:get).with("IEC 60027-1/Amd 2", nil, {}).and_return item2
        bib = @db.fetch "IEC 60027-1, Amd 1, Amd 2"
        expect(bib.docidentifier[0].id).to eq "IEC 60027-1, Amd 1, Amd 2"
        expect(bib.relation[0].type).to eq "updates"
        expect(bib.relation[0].bibitem.docidentifier[0].id).to eq "IEC 60027-1"
        expect(bib.relation[1].type).to eq "complements"
        expect(bib.relation[1].description.content).to eq "amendment"
        expect(bib.relation[1].bibitem.docidentifier[0].id).to eq "IEC 60027-1/AMD1:1997"
        expect(bib.relation[2].type).to eq "complements"
        expect(bib.relation[2].description.content).to eq "amendment"
        expect(bib.relation[2].bibitem.docidentifier[0].id).to eq "IEC 60027-1/AMD2:2005"
      end
    end

    context "ITU" do
      it "included" do
        require "relaton_itu"
        docid = RelatonBib::DocumentIdentifier.new(id: "ITU-T G.989.2", type: "ITU")
        group = RelatonItu::ItuGroup.new(name: "Group")
        ed = RelatonItu::EditorialGroup.new(bureau: "Bureau", group: group)
        item = RelatonItu::ItuBibliographicItem.new docid: [docid], editorialgroup: ed
        expect(RelatonItu::ItuBibliography).to receive(:get).with("ITU-T G.989.2", nil, {}).and_return item
        docid1 = RelatonBib::DocumentIdentifier.new(id: "ITU-T G.989.2 Amd 1", type: "ITU")
        item1 = RelatonItu::ItuBibliographicItem.new docid: [docid1], editorialgroup: ed
        expect(RelatonItu::ItuBibliography).to receive(:get).with("ITU-T G.989.2 Amd 1", nil, {}).and_return item1
        docid2 = RelatonBib::DocumentIdentifier.new(id: "ITU-T G.989.2 Amd 2", type: "ITU")
        item2 = RelatonItu::ItuBibliographicItem.new docid: [docid2], editorialgroup: ed
        expect(RelatonItu::ItuBibliography).to receive(:get).with("ITU-T G.989.2 Amd 2", nil, {}).and_return item2
        bib = @db.fetch "ITU-T G.989.2, Amd 1, Amd 2"
        expect(bib.docidentifier[0].id).to eq "ITU-T G.989.2, Amd 1, Amd 2"
        expect(bib.relation[0].type).to eq "updates"
        expect(bib.relation[0].bibitem.docidentifier[0].id).to eq "ITU-T G.989.2"
        expect(bib.relation[1].type).to eq "complements"
        expect(bib.relation[1].description.content).to eq "amendment"
        expect(bib.relation[1].bibitem.docidentifier[0].id).to eq "ITU-T G.989.2 Amd 1"
        expect(bib.relation[2].type).to eq "complements"
        expect(bib.relation[2].description.content).to eq "amendment"
        expect(bib.relation[2].bibitem.docidentifier[0].id).to eq "ITU-T G.989.2 Amd 2"
      end
    end

    context "NIST" do
      it "included" do
        # VCR.use_cassette "nist_combined_included" do
        doci = RelatonBib::DocumentIdentifier.new(id: "SP 800-38A", type: "NIST")
        item = RelatonNist::NistBibliographicItem.new docid: [doci]
        expect(RelatonNist::NistBibliography).to receive(:get).with("NIST SP 800-38A", nil, {}).and_return item
        docid1 = RelatonBib::DocumentIdentifier.new(id: "SP 800-38A-Add", type: "NIST")
        item1 = RelatonNist::NistBibliographicItem.new docid: [docid1]
        expect(RelatonNist::NistBibliography).to receive(:get).with("NIST SP 800-38A/Add", nil, {}).and_return item1
        bib = @db.fetch "NIST SP 800-38A, Add"
        expect(bib.docidentifier[0].id).to eq "NIST SP 800-38A, Add"
        expect(bib.relation[0].type).to eq "updates"
        expect(bib.relation[0].bibitem.docidentifier[0].id).to eq "SP 800-38A"
        expect(bib.relation[1].type).to eq "complements"
        expect(bib.relation[1].description.content).to eq "amendment"
        expect(bib.relation[1].bibitem.docidentifier[0].id).to eq "SP 800-38A-Add"
        # end
      end
    end
  end

  context "version control" do
    before(:each) { @db.save_entry "iso(test_key)", "<bibitem><title>test_value</title></bibitem>" }

    it "shoudn't clear cache if version isn't changed" do
      testcache = @db.instance_variable_get :@db
      expect(testcache.all).to be_any
      testcache = @db.instance_variable_get :@local_db
      expect(testcache.all).to be_any
    end

    it "should clear cache if version is changed" do
      expect(File.read("testcache/iso/version", encoding: "UTF-8")).not_to eq "new_version"
      expect(File.read("testcache2/iso/version", encoding: "UTF-8")).not_to eq "new_version"
      processor = double "processor", short: :relaton_iso
      expect(processor).to receive(:grammar_hash).and_return("new_version").exactly(2).times
      expect(Relaton::Registry.instance).to receive(:by_type).and_return(processor).exactly(2).times
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
        expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      end
    end

    it "if unavailable then get document directly" do
      expect(Net::HTTP).to receive(:get_response).and_wrap_original do |m, *args|
        raise Errno::ECONNREFUSED if args[0].host == "api.relaton.org"

        m.call(*args)
      end.at_least :once
      VCR.use_cassette "api_relaton_org_unavailable" do
        bib = @db.fetch "ISO 19115-2", "2019"
        expect(bib).to be_instance_of RelatonIsoBib::IsoBibliographicItem
      end
    end
  end
end
