module Crucible
  module Tests
    class SprinklerSearchTest < BaseTest

      def id
        'Search001'
      end

      def description
        'Initial Sprinkler tests () for testing search capabilities.'
      end

      def setup
        @resources = Crucible::Generator::Resources.new
        @patient = @resources.example_patient

        @create_date = Time.now.utc

        @version = []
        result = @client.create(@patient)
        @id = result.id
        @version << result.version

        @patient.telecom << FHIR::Contact.new(system: 'email', value: 'foo@example.com')

        update_result = @client.update(@patient, @id)
        @version << update_result.version

        reply = @client.read_feed(FHIR::Patient)
        @total_count = 0
        @entries = []

        while reply != nil
          @total_count += reply.resource.entries.count
          @entries += reply.resource.entries
          reply = @client.next_page(reply)
        end

        # create a condition matching the first patient
        @condition = ResourceGenerator.generate(FHIR::Condition,1)
        @condition.subject.id = @entries[0].resource_id
        @condition.subject.reference = @entries[0].resource_url
        reply = @client.create(@condition)
        @condition_id = reply.id

        # create some observations
        @obs_a = create_observation(4.12345)
        @obs_b = create_observation(4.12346)
        @obs_c = create_observation(4.12349)
      end

      def create_observation(value)
        observation = FHIR::Observation.new
        observation.status = 'preliminary'
        observation.reliability = 'questionable'
        code = FHIR::Coding.new
        code.system = 'http://loinc.org'
        code.code = '2164-2'
        observation.name = FHIR::CodeableConcept.new
        observation.name.coding = [ code ]
        observation.valueQuantity = FHIR::Quantity.new
        observation.valueQuantity.system = 'http://unitofmeasure.org'
        observation.valueQuantity.value = value
        observation.valueQuantity.units = 'mmol'
        body = FHIR::Coding.new
        body.system = 'http://snomed.info/sct'
        body.code = '182756003'
        observation.bodySite = FHIR::CodeableConcept.new
        observation.bodySite.coding = [ body ]
        reply = @client.create(observation)
        reply.id
      end

      def teardown
        @client.destroy(FHIR::Patient, @id)
        @client.destroy(FHIR::Condition, @condition_id)
        @client.destroy(FHIR::Observation, @obs_a)
        @client.destroy(FHIR::Observation, @obs_b)
        @client.destroy(FHIR::Observation, @obs_c)
      end

      test 'SE01','Search patients without criteria (except _count)' do
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              '_count' => '1'
            }
          }
        }
        reply = @client.search(FHIR::Patient, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.all_entries.size, 'The server did not return the correct number of results.'
        warning { assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.' }
      end

      test 'SE02', 'Search on non-existing resource' do
        options = {
          :resource => Crucible::Tests::SprinklerSearchTest,
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => nil
          }
        }
        reply = @client.search_all(options)
        assert_response_not_found(reply)
      end

      test 'SE03','Search patient resource on partial family surname' do
        search_string = @patient.name[0].family[0][0..2]
        search_regex = Regexp.new(search_string)
        # how many patients in the bundle have matching names?
        expected = 0
        @entries.each do |entry|
          patient = entry.resource
          isMatch = false
          patient.name.each do |name|
            name.family.each do |family|
              if !(family =~ search_regex).nil?
                isMatch = true
              end
            end
          end
          expected += 1 if isMatch
        end

        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'family' => search_string
            }
          }
        }
        reply = @client.search(FHIR::Patient, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal expected, reply.resource.size, 'The server did not report the correct number of results.'
      end

      test 'SE04', 'Search patient resource on given name' do
        search_string = @patient.name[0].given[0]
        search_regex = Regexp.new(search_string)
        # how many patients in the bundle have matching names?
        expected = 0
        @entries.each do |entry|
          patient = entry.resource
          isMatch = false
          patient.name.each do |name|
            name.given.each do |given|
              if !(given =~ search_regex).nil?
                isMatch = true
              end
            end
          end
          expected += 1 if isMatch
        end

        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'given' => search_string
            }
          }
        }
        reply = @client.search(FHIR::Patient, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal expected, reply.resource.size, 'The server did not report the correct number of results.'        
      end

      test 'SE05.0', 'Search condition by subject reference url' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_url = @entries[0].resource_url

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject' => patient_url
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end

      test 'SE05.1', 'Search condition by subject reference id' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_id = @entries[0].resource_id

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject' => patient_id
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end

      test 'SE05.2', 'Search condition by subject:Patient reference url' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_url = @entries[0].resource_url

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject:Patient' => patient_url
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end   

      test 'SE05.3', 'Search condition by subject:Patient reference id' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_id = @entries[0].resource_id

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject:Patient' => patient_id
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end   

      test 'SE05.4', 'Search condition by subject:_id reference' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_id = @entries[0].resource_id

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject._id' => patient_id
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end   

      test 'SE05.5', 'Search condition by subject:name reference' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_name = patient.name[0].family[0]

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject.name' => patient_name
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end   

      test 'SE05.6', 'Search condition by subject:identifier reference' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_identifier = patient.identifier[0].value

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              'subject.identifier' => patient_identifier
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert_equal 1, reply.resource.size, 'The server did not report the correct number of results.'        
      end  

      test 'SE06', 'Search condition by _include' do
        # pick some search parameters... we previously created
        # a condition for the first (0-index) patient in the setup method.
        patient = @entries[0].resource
        patient_identifier = patient.identifier[0].value

        # next, we're going execute a series of searches for conditions referencing the patient
        options = {
          :search => {
            :flag => true,
            :compartment => nil,
            :parameters => {
              '_include' => 'Condition.subject'
            }
          }
        }
        reply = @client.search(FHIR::Condition, options)
        assert_response_ok(reply)
        assert_bundle_response(reply)
        assert reply.resource.size > 0, 'The server should have Conditions with _include=Condition.subject.'        
      end         

    end
  end
end
