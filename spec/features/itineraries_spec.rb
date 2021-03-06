require 'spec_helper'

describe 'Itineraries' do
  ROUND_TRIP_ICON = 'icon-exchange'
  DAILY_ICON = 'icon-repeat'
  PINK_ICON = 'icon-lock'
  XSS_ALERT = "<script>alert('toasty!);</script>"

  describe 'Registered Users' do
    def login_as_male
      @user = FactoryGirl.create :user, uid: '123456', gender: 'male'
      visit '/auth/facebook'
    end

    def login_as_female
      @user = FactoryGirl.create :user, uid: '123456', gender: 'female'
      @old_mocked_authhash = OMNIAUTH_MOCKED_AUTHHASH
      OmniAuth.config.mock_auth[:facebook] = OMNIAUTH_MOCKED_AUTHHASH.merge extra: { raw_info: { gender: 'female' } }
      visit '/auth/facebook'
      OmniAuth.config.mock_auth[:facebook] = @old_mocked_authhash
    end

    it "are allowed to create itineraries", js: true do
      login_as_female
      visit new_itinerary_path
      fill_in 'itinerary_start_address', with: 'Milan'
      fill_in 'itinerary_end_address', with: 'Turin'
      click_button 'get-route'
      click_button 'wizard-next-step-button'

      check 'itinerary_round_trip'

      leave_date = Time.parse("#{10.days.from_now.to_date} 8:30")
      select leave_date.day, from: 'itinerary_leave_date_3i'
      select I18n.t('date.month_names')[leave_date.month], from: 'itinerary_leave_date_2i'
      select leave_date.year, from: 'itinerary_leave_date_1i'
      select '08 AM', from: 'itinerary_leave_date_4i'
      select leave_date.min, from: 'itinerary_leave_date_5i'

      return_date = Time.parse("#{35.days.from_now.to_date} 9:10")
      select return_date.day, from: 'itinerary_return_date_3i'
      select I18n.t('date.month_names')[return_date.month], from: 'itinerary_return_date_2i'
      select return_date.year, from: 'itinerary_return_date_1i'
      select '09 AM', from: 'itinerary_return_date_4i'
      select return_date.min, from: 'itinerary_return_date_5i'

      fill_in 'itinerary_fuel_cost', with: '5'
      fill_in 'itinerary_tolls', with: '3'

      fill_in 'itinerary_description', with: 'MUSIC VERY LOUD!!!'
      check 'itinerary_pink'
      check 'itinerary_pets_allowed'
      click_button 'new_itinerary_submit'

      expect(page).to have_content I18n.t('flash.itineraries.success.create')
      expect(page).to have_content 'Milan'
      expect(page).to have_content 'Turin'
      expect(page).to have_content I18n.l(leave_date, format: :long)
      expect(page).to have_content I18n.l(return_date, format: :long)
      expect(page).to have_content '5.00'
      expect(page).to have_content '3.00'
      expect(page).to have_content Itinerary.human_attribute_name(:pink)
      expect(page).to have_content I18n.t("itineraries.show.pets.allowed")
      expect(page).to have_content I18n.t("itineraries.show.smoking.forbidden")
      expect(page).to have_content 'MUSIC VERY LOUD!!!'
    end

    it "sanitize malicious description" do
      login_as_male
      malicious_itinerary = FactoryGirl.create :itinerary, user: @user, description: XSS_ALERT
      #pending
    end

    it "allow users to search them", js: true do
      login_as_male
      FactoryGirl.create :itinerary, round_trip: true
      FactoryGirl.create :itinerary
      visit itineraries_path
      fill_in 'itineraries_search_from', with: 'Milan'
      fill_in 'itineraries_search_to', with: 'Turin'
      click_button 'itineraries-search'
      expect(page).to have_css('.itinerary-thumbnail', count: 2)
    end

    it "allow users to view their own ones" do
      login_as_female
      FactoryGirl.create :itinerary, user: @user
      FactoryGirl.create :itinerary, user: @user, round_trip: true
      FactoryGirl.create :itinerary, user: @user, daily: true
      FactoryGirl.create :itinerary, user: @user, pink: true, daily: true
      visit itineraries_user_path(@user)
      expect(page).to have_css('tbody > tr', count: 4)
      @user.itineraries.each do |itinerary|
        row = find(:xpath, "//a[@href='#{itinerary_path(itinerary)}' and text()='#{itinerary.start_address}']/../..")
        expect(row).to_not be_nil
        expect(row).to have_css "i.#{ROUND_TRIP_ICON}" if itinerary.round_trip?
        expect(row).to have_css "i.#{DAILY_ICON}" if itinerary.daily?
        expect(row).to have_css "i.#{PINK_ICON}" if itinerary.pink?
      end
    end

    it "allow users to delete their own ones" do
      login_as_male
      itinerary = FactoryGirl.create :itinerary, user: @user
      visit itineraries_user_path(@user)
      find(:xpath, "//a[@data-method='delete' and @href='#{itinerary_path(itinerary)}']").click
      expect(page).to have_content I18n.t('flash.itineraries.success.destroy')
      expect(page).to_not have_content itinerary.title
    end

    it "allow users to edit their own ones" do
      login_as_male
      itinerary = FactoryGirl.create :itinerary, user: @user, description: 'Old description'
      visit itineraries_user_path(@user)
      find(:xpath, "//a[contains(@href, '#{edit_itinerary_path(itinerary)}')]").click
      fill_in 'itinerary_description', with: 'New Description'
      click_button I18n.t('helpers.submit.update', model: Itinerary.model_name.human)
      expect(page).to have_content I18n.t('flash.itineraries.success.update')
      expect(page).to have_content 'New Description'
    end

    it "doesn't allow male users to see pink itineraries" do
      login_as_male
      female_user = FactoryGirl.create :user, gender: 'female'
      pink_itinerary = FactoryGirl.create :itinerary, user: female_user, description: 'Pink itinerary', pink: true
      visit itinerary_path(pink_itinerary)
      expect(current_path).to eq dashboard_path
      expect(page).to have_content I18n.t('flash.itineraries.error.pink')
    end
  end

  describe 'Guests' do
    it "allow guests to see itineraries" do
      itinerary = FactoryGirl.create :itinerary, description: 'Itinerary for guest users'
      visit itinerary_path(itinerary)
      expect(current_path).to eq itinerary_path(itinerary)
      expect(page).to have_content itinerary.description
    end

    it "doesn't allow guests to see pink itineraries" do
      female_user = FactoryGirl.create :user, gender: 'female'
      pink_itinerary = FactoryGirl.create :itinerary, user: female_user, description: 'Pink itinerary', pink: true
      visit itinerary_path(pink_itinerary)
      expect(current_path).to eq root_path
    end
  end
end
