module QuizQuestion::AnswerSerializers
  class AnswerSerializer
    attr_accessor :question

    def initialize(question)
      self.question = question
    end

    # Serialize the user-supplied answer into a format compatible with
    # QuizSubmission#submission_data.
    #
    # @param [Mixed] answer
    #   The user-supplied answer. The type of this argument may change between
    #   serializers. See related AnswerSerializer documentation for the answer
    #   format they accept.
    #
    # @return [SerializedAnswer]
    def serialize(answer)
      raise NotImplementedError
    end

    # Convert serialized answers from QuizSubmission#submission_data to something
    # presentable to the user.
    #
    # @note
    #   The format of the output of this method must match the format of the
    #   user-supplied answer. See #serialize.
    #
    # @return [Any]
    #   The output is similar to the user-supplied answer, which may vary between
    #   serializers.
    def deserialize(submission_data)
      raise NotImplementedError
    end

    # Automatically register answer serializers. Each serializer will be mapped
    # to the QuizQuestion of a type that is deduced from the serializer's class
    # name.
    #
    # See #question_type
    def self.inherited(klass)
      QuizQuestion::AnswerSerializers.register_serializer klass.question_type, klass
    end

    # Override this to explicitly specify the question_type the serializer works
    # for.
    def self.question_type
      self.name.demodulize.underscore
    end

    protected

    # The hash-key of the question answer record in the submission_data.
    #
    # This varies between question types, so some serializers will override this.
    def question_key
      @question_key ||= [ 'question', self.question.id ].join('_')
    end

    # Locate the question data that is usable by *students* when they take the
    # quiz, which might be different than the data of @question because the
    # teacher might be editing the question and has not yet published the
    # changes, in which case the students should use the "frozen" version of
    # the question and not the not-yet-published one.
    #
    # The data set is retrieved from Quiz#quiz_data, if that is not yet generated,
    # it falls back to Quiz#stored_questions, and if that still doesn't contain
    # our question, it falls back to QuizQuestion#question_data.
    #
    # Please make sure that you use this data set for any lookups of answer IDs,
    # matches, or whatever.
    #
    # @return [Hash] The question data.
    def frozen_question_data
      @frozen_question_data ||= begin
        question_id = self.question.id
        quiz = self.question.quiz
        quiz_data = quiz.quiz_data || quiz.stored_questions
        quiz_data.detect { |question| question[:id].to_i == question_id } ||
          self.question.question_data
      end
    end

    # @return [Array<Hash>] Set of answer records for the frozen question.
    def answers
      @answers ||= frozen_question_data[:answers]
    end

    # @return [Array<Integer>] Set of IDs for all the question answers.
    def answer_ids
      @answer_ids ||= answers.map { |answer| answer[:id].to_i }
    end

    # @return [Boolean] True if the answer_id identifies a known answer
    def answer_available?(answer_id)
      answer_ids.include?(answer_id.to_i)
    end
  end

  class << self
    attr_accessor :serializers

    def register_serializer(question_type, serializer)
      self.serializers ||= {}
      self.serializers[question_type] = serializer
    end

    # Get an instance of an AnswerSerializer appropriate for the given question.
    #
    # @param [QuizQuestion] question
    #   The question to locate the serializer for.
    #
    # @return [AnswerSerializer]
    #   The serializer.
    #
    # @throw RuntimeError if no serializer was found for the given question
    def serializer_for(question)
      self.serializers ||= {}

      question_type = question.respond_to?(:data) ?
        question.data[:question_type] :
        question[:question_type]

      question_type.gsub! /_question$/, ''

      unless serializer_klass = self.serializers[question_type]
        raise "No known serializer for questions of type #{question_type}"
      end

      serializer_klass.new(question)
    end
  end
end