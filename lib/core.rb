require_relative 'publications_classes'
require_relative 'personnel_classes'
require_relative 'funding_classes'
require 'pony'
require 'open3'
require 'securerandom'

def get_databases
  [%w[Publications publications], %w[Personnel personnel], %w[Funding funding]]
end


def generate_questionnaire(questionnaire_type:) # questionnaire_type comes in as code only

  Questionnaire.new(questionnaire_type: questionnaire_type) # questionnaire_type comes in as just the id)
  # warn questionnaire.inspect
end

# def generate_form(form: , lang: "EN") # questionnaire_type comes in as code only
#   res = get_form_fields_query(form: form, lang: lang) # SELECT ?field ?label ?widget ?cardinality 
#   warn res.inspect
#   fields = {}
#   res.each do |r|
#     fields[r["field"].to_s] = {}
#     fields[r["field"].to_s]["label"] = r["label"].to_s
#     fields[r["field"].to_s]["widget"] = r["widget"].to_s
#     fields[r["field"].to_s]["cardinality"] = r["cardinality"].to_s
#   end
#   warn "FIELDS"
#   # warn fields.inspect
#   # {"https://w3id.org/CBGP-App#publication-affiliations"=>
#   #   {"label =>"Affiliations", "widget"=>"https://w3id.org/CBGP-App#text", "cardinality"=>"multi"}, 
#   # "https://w3id.org/CBGP-App#publication-authors"=>
#   #   {"label =>"Authors", ...
#   #   {"label =>"Date", ...
#   #   {"label =>"DOI", ...
#   #   {"label =>"Title", ...
#   # }
#   fields
# end

def get_questionnaire_languages
  langs = query_questionnaire_languages
  # SELECT distinct (lang(?ql) as ?lang) WHERE {
  languages = []
  langs.each do |lang|
    languages << [lang[:lang].to_s.upcase, lang[:lang].to_s.upcase]
  end
  warn "languages #{languages.inspect}"
  languages
end

def get_questionnaire_types
  [%w[Patient Child], %w[Patient Adult], %w[Professional Child], %w[Professional Adult]].each do |p, c|
    resp = get_sections_labels(lang: 'EN', patprof: p, adultchild: c)
    # select ?q (str(?ql) as ?qlabel) ?pp (str(?ppl) as ?pplabel) ?ac (str(?acl) as ?aclabel)
    resp.first[:q] # need to get just the number
  end
  [['QPAA0', 'Patient Adult'], ['QPAC0', 'Patient Child'], ['QPRA0', 'Professional Adult'],
   ['QPRC0', 'Professional Child']]
end

def get_centers
  results = read_centers_from_db
  @langs = get_questionnaire_languages
  @types = get_questionnaire_types

  # select ?g ?id ?email ?applicant ?name ?country ?name where {
  # TODO   Fix this redundancy with get_center
  centers = []
  results.each do |r|
    graph = r[:g].to_s
    id = r[:id].to_s
    email = r[:email].to_s
    name = r[:name].to_s
    applicant = r[:applicant]
    country = r[:country]
    visibility = r[:visibility] || 'visible'
    status = r[:status] || 'OPEN'
    id = id.match(%r{/(\d+)/center})[1] # just get the numerical value

    centers << Center.new(name: name, email: email, applicant: applicant, country: country, id: id, graph: graph,
                          status: status, visibility: visibility)
  end
  centers
end

def hide_center(centerid:)
  center = get_center(centerid: centerid)
  center.visibility = 'hidden'
  center.write_to_db
end

def unhide_center(centerid:)
  center = get_center(centerid: centerid)
  center.visibility = 'visible'
  center.write_to_db
end

def delete_center(centerid:)
  delete_center_query(centerid: centerid)
end

def get_center(centerid:)
  centers = get_centers
  center = centers.select { |c| c.id == centerid }
  center.first
end

def submit_answers(submission:)
  # submission is the full @parms from teh web form (its a hash)
  # warn "submission is #{submission}"

  centerid = submission.delete('center')
  patprof = submission.delete('patprof')
  adultchild = submission.delete('adultchild')
  questionnaire_type = submission.delete('qtype')
  original_language = submission.delete('lang') || 'EN'

  unhide_center(centerid: centerid) # any action will cause the center to become visible again
  center = get_center(centerid: centerid)

  now = Time.now
  questionnaireid = now.to_i
  date = now.strftime '%Y-%m-%d'

  submission.each do |qid, a|
    if a.is_a? Array
      a.each do |answer|
        answer.strip!
        next if answer.empty?

        write_question_answer_pair(centerid: centerid, questionnaireid: questionnaireid, qid: qid, answer: answer)
      end
    else
      a.strip!
      next if a.empty?

      write_question_answer_pair(centerid: centerid, questionnaireid: questionnaireid, qid: qid, answer: a)
    end
  end
  write_questionnaire_metadata(centerid: centerid, questionnaireid: questionnaireid, date: date, patprof: patprof,
                               adultchild: adultchild, questionnaire_type: questionnaire_type, original_language: original_language)
  _update_center_status(centerid: centerid, status: "A #{date}") # status is "answers received"
  subject = 'Accredited Centers: Questionnaire answers have been submitted'
  message = <<EOM
  Questionnaire answers have been submitted from #{center.name}.#{' '}
   Go directly to the list of Center submissions by following this Link:
  https://accredited.worldduchenne.org/adc/retrieve-questionnaires/#{centerid}

EOM
  _send_notification(centerid: centerid, subject: subject, message: message)
end

def _update_center_status(centerid:, status:)
  center = get_center(centerid: centerid)
  center.status = status # update center status as "answered" or "commented", etc.
  center.write_to_db
  true
end

def _send_notification(centerid:, subject:, message:)
  Pony.mail({
              to: NOTIFY_TO,
              from: 'accreditation@worldduchenne.org',
              subject: subject,
              body: message,
              via: :smtp,
              via_options: {
                address: 'mail.fairdata.systems',
                port: '587',
                enable_starttls_auto: true,
                user_name: NOTIFY_UN,
                password: NOTIFY_PW,
                authentication: 'login' # :plain, :login, :cram_md5, no auth by default
              }
            })
end

def create_pdf(html:)
  FileUtils.rm_rf Dir.glob('./public/images/*.html')
  FileUtils.rm_rf Dir.glob('./public/images/*.pdf')

  name = SecureRandom.uuid
  File.open("./public/images/#{name}.html", 'w') do |f|
    f.write html
  end
  _o, _s = Open3.capture2("wkhtmltopdf ./public/images/#{name}.html ./public/images/#{name}.pdf")
  # warn o
  # warn s
  # sleep 5
  "/images/#{name}.pdf"
end

def write_comments_to_db(params:, lang: 'EN')
  # <input type="hidden" name="questionnaireid" value="1719144108"/>
  # <input type="hidden" name="center" value="1718454609"/>
  centerid = params.delete('center')
  questionnaireid = params.delete('questionnaireid')
  params.each do |sectionid, comment|
    # we want to replace comments with the same language, but leave all other comments in other languages
    clean_comment_from_db_query(centerid: centerid, questionnaireid: questionnaireid, sectionid: sectionid,
                                comment: comment, lang: lang)
    write_comment_to_db_query(centerid: centerid, questionnaireid: questionnaireid, sectionid: sectionid,
                              comment: comment, lang: lang)
  end
end

def write_responses_to_db(params:, lang: 'EN')
  # <input type="hidden" name="questionnaireid" value="1719144108"/>
  # <input type="hidden" name="center" value="1718454609"/>
  centerid = params.delete('center')
  center = get_center(centerid: centerid)
  unhide_center(centerid: centerid) # any action will cause the center to become visible again

  questionnaireid = params.delete('questionnaireid')
  params.each do |sectionid, response|
    # we want to replace comments with the same language, but leave all other comments in other languages
    # clean_comment_from_db_query(centerid: centerid, questionnaireid: questionnaireid, sectionid: sectionid,
    #                             comment: comment, lang: lang)
    write_response_to_db_query(centerid: centerid, questionnaireid: questionnaireid, sectionid: sectionid,
                               response: response, lang: lang)
  end
  subject = 'Accredited Centers: Responses to ADC Comments have been received'
  message = <<EOR
  Responses to ADC staff comments have been received from #{center.name}.#{' '}
   To see these responses, click the "Final Report" button for the appropriate questionnaire.#{' '}
  #{' '}
   Go directly to the list of Center submissions by following this link:
   https://accredited.worldduchenne.org/adc/retrieve-questionnaires/#{centerid}

EOR
  _send_notification(centerid: centerid, subject: subject, message: message)
end

def retrieve_questionnaires(centerid:)
  questionnaires = []
  results = retrieve_questionnaires_query(centerid: centerid)
  # SELECT ?qgraph ?date ?qid ?patprof ?adultchild ?qtype where {
  results.each do |res|
    questionnaires << { qgraph: res[:qgraph].to_s, date: res[:date].to_s,
                        type: res[:patprof].to_s + ' ' + res[:adultchild].to_s,
                        questionnaire_type: res[:qtype].to_s, qid: res[:qid].to_s }
  end
  questionnaires
end

def generate_questionnaire_link(centerid:, lang:, type:)
  _center = get_center(centerid: centerid)
  now = Time.now
  date = now.strftime '%Y-%m-%d'
  _update_center_status(centerid: centerid, status: "Q #{date}") # mark questionnaire sent
  "https://accredited.worldduchenne.org/adc/generate-questionnaire/#{centerid}?lang=#{lang}&type=#{type}" # ?type=QPAC0&lang=EN
end

def comment_on_questionnaire(centerid:, questionnaireid:, lang: 'EN')
  res = retrieve_questionnaire_metadata_query(questionnaireid: questionnaireid, centerid: centerid) # ?qgraph ?date ?patprof ?adultchild ?qtype ?lang
  patprof = res.first[:patprof].to_s
  adultchild = res.first[:adultchild].to_s
  questionnaire_type = res.first[:qtype].to_s
  original_language = res.first[:lang].to_s
  completed_questionnaire = Questionnaire.new(patprof: patprof, adultchild: adultchild,
                                              questionnaire_type: questionnaire_type, questionnaireid: questionnaireid, lang: lang)
  completed_questionnaire.sections.each do |section|
    section.questions.each do |question|
      answers = []
      results = read_question_answer_pair(centerid: centerid, questionnaireid: questionnaireid,
                                          qid: question.questionid)
      warn "Result from #{question.questionid}  #{results.inspect}"
      results.each do |resu|
        answerid = resu[:answer]
        answerid = [answerid.to_s] unless answerid.is_a? Array
        warn "answerid #{answerid}"
        answerid.each do |thisans| # still sparql result objects
          thisanswer = thisans.to_s
          answers << if thisanswer.match(/\w\w\w\d+-\d+/)
                       get_label_for_id(id: thisanswer, lang: lang)
                     else
                       thisanswer
                     end
        end
      end
      question.selected_answer = answers
    end
  end
  #  abort "retrieve comments query lang #{lang}"
  # results = retrieve_comments_query(centerid: centerid, questionnaireid: questionnaireid, lang: lang)
  # comments are always in English at the moment, so... default to english
  # since what is coming in lang is the default response language
  results = retrieve_comments_query(centerid: centerid, questionnaireid: questionnaireid, lang: 'EN')
  # SELECT ?section ?comment  (<urn:local:section:#{sectionid}:comment>_ ?comment)
  comments = {}
  results.each do |resu|
    section = resu[:section].to_s.match(/local:section:([^:]+):comment/)[1]
    comments[section] = resu[:comment].to_s # build the hash
  end

  [completed_questionnaire, comments, original_language]
end

def report_on_questionnaire(centerid:, questionnaireid:, lang: 'EN')
  res = retrieve_questionnaire_metadata_query(questionnaireid: questionnaireid, centerid: centerid) # ?qgraph ?date ?patprof ?adultchild ?qtype ?lang
  patprof = res.first[:patprof].to_s
  adultchild = res.first[:adultchild].to_s
  questionnaire_type = res.first[:qtype].to_s
  original_language = res.first[:lang].to_s
  completed_questionnaire = Questionnaire.new(patprof: patprof, adultchild: adultchild,
                                              questionnaire_type: questionnaire_type, questionnaireid: questionnaireid, lang: lang)
  completed_questionnaire.sections.each do |section|
    section.questions.each do |question|
      answers = []
      results = read_question_answer_pair(centerid: centerid, questionnaireid: questionnaireid,
                                          qid: question.questionid)
      warn "Result from #{question.questionid}  #{results.inspect}"
      results.each do |resu|
        answerid = resu[:answer]
        answerid = [answerid.to_s] unless answerid.is_a? Array
        warn "answerid #{answerid}"
        answerid.each do |thisans| # still sparql result objects
          thisanswer = thisans.to_s
          answers << if thisanswer.match(/\w\w\w\d+-\d+/)
                       get_label_for_id(id: thisanswer, lang: lang)
                     else
                       thisanswer
                     end
        end
      end
      question.selected_answer = answers
    end
  end

  lang = 'EN'
  results = retrieve_comments_query(centerid: centerid, questionnaireid: questionnaireid, lang: lang)
  # SELECT ?section ?comment  (<urn:local:section:#{sectionid}:comment> ?comment)
  comments = {}
  results.each do |resu|
    section = resu[:section].to_s.match(/local:section:([^:]+):comment/)[1]
    comments[section] = resu[:comment].to_s # build the hash
  end

  results = retrieve_responses_query(centerid: centerid, questionnaireid: questionnaireid, lang: lang)
  # SELECT ?section ?response  (<urn:local:section:#{sectionid}:response> ?response)
  responses = {}
  results.each do |resu|
    section = resu[:section].to_s.match(/local:section:([^:]+):response/)[1]
    responses[section] = resu[:response].to_s # build the hash
  end

  [completed_questionnaire, comments, responses, original_language]
end

def generate_commented_questionnaire_link(centerid:, questionnaireid:)
  res = retrieve_questionnaire_metadata_query(questionnaireid: questionnaireid, centerid: centerid) # ?qgraph ?date ?patprof ?adultchild ?qtype ?lang
  original_language = res.first[:lang].to_s

  center = get_center(centerid: centerid)
  now = Time.now
  date = now.strftime '%Y-%m-%d'
  center.status = "C #{date}"
  center.write_to_db
  "https://accredited.worldduchenne.org/adc/retrieve-commented-questionnaire/#{centerid}/#{questionnaireid}?lang=#{original_language}"
end
