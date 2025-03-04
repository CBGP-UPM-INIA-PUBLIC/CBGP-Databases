require_relative "./queries"
require_relative "./core"

class Questionnaire
  attr_accessor :questionnaire_type, :sections, :lang, :questionnaireid
  attr_accessor :status

  def initialize() # questionnaire_type comes in as just the id

    # GET THE LABELS HERE
    @lang = lang.upcase
    @questionnaire_type = questionnaire_type  # its GUID as only the #code
    @patprof = patprof #  english label
    @adultchild = adultchild  # english label
    @sections = fill_category_sections
    @questionnaireid = questionnaireid
    @status = status
  end

  def fill_category_sections
    sects = []
    warn "getting category sections #{@questionnaire_type}"
    results = get_questionnaire_sections_query(questionnaire_type: @questionnaire_type) 
    #    SELECT ?sec (str(?seclab) as ?label)
    #    warn "getting category sections #{results.inspect}"

    results.each do |res|  # get general information first
      section = res[:sec].to_s # comes in as full URL
      sectionid = section.gsub(/.*\#/, "") # remove everything up to the hash in the URL
      warn "getting section #{section}"
      seclabel = res[:label].to_s
      if %w[QPAA19 QPAC17 QPRA17 QPRC18].include? sectionid  # these are the "general information" sections
        sects.unshift QuestionnaireSection.new(sectionid: sectionid, sectionlabel: seclabel)
        # put General Information on the top!
      else
        sects << QuestionnaireSection.new(sectionid: sectionid, sectionlabel: seclabel)
      end
    end
    sects
  end
end

class QuestionnaireSection
  attr_accessor :sectionid, :questions, :sectionlabel, :lang, :wdo_comment, :center_response

  def initialize(sectionid:, sectionlabel:, lang:)  # sectionid comes in as identifier only
    @lang = lang
    @sectionid = sectionid
    @sectionlabel = sectionlabel
    @questions = get_questions
    @wdo_comment = nil
    @center_response = nil
  end

  def get_questions
    qs = []
    results = get_section_questions_query(sectionid: @sectionid, lang: @lang) #  SELECT ?q (str(?qlab) as ?label) ?answers ?order
    results.each do |res|
      qurl = res[:q].to_s # comes in as full URL
      qid = qurl.gsub(/.*\#/, "") # everything up to the hash in the URL
      question = res[:label].to_s
      answerblock = res[:answers].to_s # check that this is a URI an dnot a fr4agtment
      answerblockid = answerblock.gsub(/.*\#/, "") # everything up to the hash in the URL
      sequence = res[:sequence].to_i
      qs << QuestionnaireQuestion.new(questionid: qid, question: question, answerblockid: answerblockid, sequence: sequence, lang: @lang)
    end
    qs
  end
end

class QuestionnaireQuestion
  attr_accessor :questionid, :sequence, :answerblock, :question, :lang, :selected_answer

  def initialize(questionid:, sequence:, answerblockid:, question:, lang:)  # questionid and answerblockid comes in as fragment only
    @question = question  # text in the correct language
    @questionid = questionid
    @sequence = sequence
    @answerblockid = answerblockid
    @selected_answer = nil
    @lang = lang

    #  when answervblockid is OPEN or NUM then the AnswerBlock objects will not have answers... we can catch that!
    #<QuestionnaireQuestion:0x000055b680382cc8
    # @answerblock=#<QuestionnaireAnswerBlock:0x000055b680382c78 @ablockid="OPEN", @answers=[], @lang="EN">,
    # @answerblockid="OPEN",
    # @lang="EN",
    # @question="Comments/suggestions",
    # @questionid="FAQN3",
    # @sequence=3>],


    @answerblock = QuestionnaireAnswerBlock.new(ablockid: @answerblockid, lang: @lang)
  end
end

class QuestionnaireAnswerBlock
  attr_accessor :ablockid, :answers, :lang, :type

  def initialize(ablockid:, lang:)  # ablockid comes in as fragment only
    @ablockid = ablockid
    @lang = lang
    @answers = []

    if @ablockid == "OPEN"
      @type = "OPEN"
    elsif @ablockid == "NUM"
      @type = "NUM"
    else
      results = get_answer_block_query(ablockid: @ablockid, lang: @lang) #    SELECT DISTINCT ?aid ?label ?order ?widget
      results.each do |result|
        answers << QuestionnaireAnswer.new(answerid: result[:aid].to_s, answer: result[:label].to_s, 
                                          sequence: result[:sequence].to_i, widget: result[:widget].to_s, lang: @lang)
        @type = result[:widget].to_s # it should always be the same for every answer, so... just grab one!
      end
    end
  end
end

class QuestionnaireAnswer
  attr_accessor :answerid, :widget, :answer, :lang, :sequence

  def initialize(answerid:, lang:, answer:, sequence:, widget:)
    @answerid = answerid
    @answerid = @answerid.gsub(/.*\#/, "") # everything up to the hash in the URL

    @sequence = sequence
    @lang = lang
    @answer = answer
    @widget = widget
  end
end
